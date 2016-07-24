{-# Language TemplateHaskell #-}

{-|
Module      : Client.ChannelState
Description : IRC channel session state
Copyright   : (c) Eric Mertens, 2016
License     : ISC
Maintainer  : emertens@gmail.com

This module is responsible for tracking the state of an individual IRC
channel while the client is connected to it. When the client joins a
channel a new channel session is created and when the client leaves
a channel is it destroyed.
-}

module Client.ChannelState
  (
  -- * Channel state type
    ChannelState
  , chanTopic
  , chanTopicProvenance
  , chanUsers
  , chanModes
  , chanLists
  , chanList
  , chanCreation
  , chanQueuedModeration

  -- * Topic information
  , TopicProvenance(..)
  , topicAuthor
  , topicTime

  -- * Channel manipulation
  , newChannel
  , setTopic
  , joinChannel
  , partChannel
  , nickChange
  ) where

import           Control.Lens
import           Data.HashMap.Strict
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Map.Strict as Map
import           Data.Map.Strict (Map)
import           Data.Text (Text)
import qualified Data.Text as Text
import           Data.Time
import           Irc.Identifier
import           Irc.RawIrcMsg (RawIrcMsg)
import           Irc.UserInfo

data ChannelState = ChannelState
  { _chanTopic :: !Text
        -- ^ topic text
  , _chanTopicProvenance :: !(Maybe TopicProvenance)
        -- ^ author and timestamp for topic
  , _chanUsers :: !(HashMap Identifier String)
        -- ^ user list and sigils
  , _chanModes :: !(Map Char Text)
        -- ^ channel settings and parameters
  , _chanLists :: !(Map Char (HashMap Text (Text, UTCTime)))
        -- ^ mode, mask, setter, set time
  , _chanCreation :: !(Maybe UTCTime) -- ^ creation time of channel
  , _chanQueuedModeration :: ![RawIrcMsg] -- ^ delayed op messages
  }
  deriving Show

data TopicProvenance = TopicProvenance
  { _topicAuthor :: !UserInfo
  , _topicTime   :: !UTCTime
  }
  deriving Show

makeLenses ''ChannelState
makeLenses ''TopicProvenance

-- | Construct an empty 'ChannelState'
newChannel :: ChannelState
newChannel = ChannelState
  { _chanTopic = Text.empty
  , _chanTopicProvenance = Nothing
  , _chanUsers = HashMap.empty
  , _chanModes = Map.empty
  , _chanLists = Map.empty
  , _chanCreation = Nothing
  , _chanQueuedModeration = []
  }

-- | 'Lens' into a mask list for a given mode.
chanList ::
  Functor f =>
  Char {- ^ mode -} ->
  LensLike' f ChannelState (HashMap Text (Text, UTCTime))
chanList mode = chanLists . at mode . non' _Empty

-- | Add a user to the user list
joinChannel :: Identifier -> ChannelState -> ChannelState
joinChannel nick = set (chanUsers . at nick) (Just "")

-- | Remove a user from the user list
partChannel :: Identifier -> ChannelState -> ChannelState
partChannel nick = set (chanUsers . at nick) Nothing

-- | Rename a user in the user list
nickChange :: Identifier -> Identifier -> ChannelState -> ChannelState
nickChange fromNick toNick cs =
  set (chanUsers . at toNick) modes cs'
  where
  (modes, cs') = cs & chanUsers . at fromNick <<.~ Nothing

-- | Set the channel topic
setTopic :: Text -> ChannelState -> ChannelState
setTopic = set chanTopic
