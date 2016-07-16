{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
module CtcpHandler where

import Control.Lens
import Control.Monad
import Control.Applicative
import Control.Concurrent
import Data.ByteString (ByteString)
import Data.Monoid
import Data.Map as Map
import Data.Maybe
import Data.Time
import Data.Version (showVersion)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as B8
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

#if MIN_VERSION_time(1,5,0)
import Data.Time (defaultTimeLocale)
#else
import System.Locale (defaultTimeLocale)
#endif

import ClientState
import DCC
import ServerSettings
import Irc.Format
import Irc.Message
import Irc.Cmd
import Paths_irc_core (version)

versionString :: ByteString
versionString = "glirc " <> B8.pack (showVersion version)

sourceString :: ByteString
sourceString = "https://github.com/glguy/irc-core"

ctcpHandler :: EventHandler
ctcpHandler = EventHandler
  { _evName = "CTCP replies"
  , _evOnEvent = \_ msg st ->

       do let sender = views mesgSender userNick msg
          forOf_ (mesgType . _CtcpReqMsgType) msg $ \(command,params) ->

               -- Don't send responses to ignored users
               unless (view (clientIgnores . contains sender) st) $
                 case command of
                   "CLIENTINFO" ->
                     clientSend (ctcpResponseCmd sender "CLIENTINFO"
                                   "ACTION CLIENTINFO FINGER PING SOURCE TIME USERINFO VERSION") st
                   "VERSION" ->
                     clientSend (ctcpResponseCmd sender "VERSION" versionString) st
                   "USERINFO" ->
                     clientSend (ctcpResponseCmd sender "USERINFO"
                                    (views (clientServer0 . ccServerSettings . ssUserInfo)
                                           (Text.encodeUtf8 . Text.pack) st)) st
                   "PING" ->
                     clientSend (ctcpResponseCmd sender "PING" params) st
                   "SOURCE" ->
                     clientSend (ctcpResponseCmd sender "SOURCE" sourceString) st
                   "FINGER" ->
                     clientSend (ctcpResponseCmd sender "FINGER"
                                    "Username and idle time unavailable") st
                   "TIME" -> do
                     now <- getZonedTime
                     let resp = formatTime defaultTimeLocale "%a %d %b %Y %T %Z" now
                     clientSend (ctcpResponseCmd sender "TIME" (B8.pack resp)) st
                   _ -> return ()

          -- reschedule handler
          return (over clientAutomation (cons ctcpHandler) st)
  }

-- ideally this would be in DCC but hs-boot files are a pain
-- time limit between offer and acceptance of connection 90s.
pruneStaleOffers :: ClientState -> IO ClientState
pruneStaleOffers st =
  do now <- getCurrentTime
     let cond offer = diffUTCTime now (_doTime offer) < 90
     return $ over (clientServer0 . ccHoldDccTrans) (Map.filter cond) st

-- traverseOf means more clarity(?)
checkTransfers :: ClientState -> IO ClientState
checkTransfers = traverseOf (clientDCCTransfers . traverse)
                               (update . graduate)
  where
    update :: Transfer -> IO Transfer
    update trans
      | (Ongoing _ _ _ _ mvar) <- trans = do
            possibleProgress <- tryReadMVar mvar
            case possibleProgress of
              Just newValue -> return $ trans { _tcurSize = newValue }
              Nothing       -> return $ trans
      | otherwise = return trans

    graduate :: Transfer -> Transfer
    graduate trans
      | (Ongoing name size curSize _ _) <- trans,
        size == curSize = Finished name size
      | otherwise       = trans

dccHandler :: FilePath -> EventHandler
dccHandler outDir = EventHandler
  { _evName = "DCC handler"
  , _evOnEvent = \ident msg st ->
         return $ over clientAutomation (cons (dccHandler outDir))
                       (queueOffer outDir ident msg st)
  }

-- todo(slack): better message to the user (this is a hack)
-- | We assume ctcpHandler already ran and created the corresponding window.
userConfirm :: Identifier -> ClientState -> ClientState
userConfirm sender st =
  let questionText = PrivMsgType $ "You have a pending DCC transfer. /dcc"
                       <> " accept it or /dcc cancel"
  in addMessage sender (set mesgType questionText defaultIrcMessage) st

queueOffer :: FilePath -> Identifier -> IrcMessage
           -> ClientState -> ClientState
queueOffer outDir _ msg st = fromJust $
    (notIgnored >> isCtcpMsg >>= isDCCcommand
     >>= pure . userConfirm sender . storeOffer) <|> Just st
  where
    space = 0x20
    sender = views mesgSender userNick msg
    ctime  = view mesgStamp msg

    -- Could be an 'if then else' but the shortcircuit of Maybe is
    -- clearer. () really could be any type.
    notIgnored :: Maybe ()
    notIgnored = if not (view (clientIgnores . contains sender) st)
                    then Just () else Nothing

    isCtcpMsg :: Maybe (ByteString, ByteString)
    isCtcpMsg = preview (mesgType . _CtcpReqMsgType) msg

    isDCCcommand :: (ByteString, ByteString) -> Maybe (FourTuple ByteString)
    isDCCcommand ("DCC", params)
      | [type',  bName, bAddr, bPort, bSize] <- take 5 (B.split space params)
      , type' == "SEND" = Just (bName, bAddr, bPort, bSize)
    isDCCcommand _ = Nothing

    -- Store the offer until the user accepts it on /dcc accept
    storeOffer :: FourTuple ByteString -> ClientState
    storeOffer offer =
      set (clientServer0 . ccHoldDccTrans . at sender)
          (Just (parseDccOffer ctime outDir offer)) st

retrieveAndStartOffer :: ClientState -> Maybe (IO ClientState)
retrieveAndStartOffer st = do
  sender <- preview (clientFocus . _ChannelFocus) st
  offer  <- view (clientServer0 . ccHoldDccTrans . at sender) st
  Just $ do
    mvar     <- newMVar 0
    threadId <- forkIO (dcc_recv mvar offer)
    let transfer      = toTransfer offer threadId mvar
        removeOffer   = over (clientServer0 . ccHoldDccTrans)
                             (Map.delete sender)
        storeTransfer = over clientDCCTransfers (cons transfer)
    return . storeTransfer . removeOffer $ st
