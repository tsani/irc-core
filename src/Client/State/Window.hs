{-# Language BangPatterns, TemplateHaskell #-}

{-|
Module      : Client.State.Window
Description : Types and operations for managing message buffers.
Copyright   : (c) Eric Mertens, 2016
License     : ISC
Maintainer  : emertens@gmail.com

This module defines types and operations used to store messages for display
in the client's buffers.
-}

module Client.State.Window
  (
  -- * Windows
    Window(..)
  , winMessages
  , winUnread
  , winTotal
  , winMention

  -- * Window lines
  , WindowLine(..)
  , wlBody
  , wlText
  , wlImage
  , wlFullImage
  , wlImportance
  , wlTimestamp

  -- * Window line importance
  , WindowLineImportance(..)

  -- * Window operations
  , emptyWindow
  , addToWindow
  , windowSeen
  ) where

import           Client.Image.PackedImage
import           Client.Message
import           Control.Lens
import           Data.Text (Text)
import           Data.Time (UTCTime)

-- | A single message to be displayed in a window
data WindowLine = WindowLine
  { _wlBody       :: !MessageBody -- ^ Original Haskell value
  , _wlText       :: {-# UNPACK #-} !Text -- ^ Searchable text form
  , _wlImage      :: !Image'      -- ^ Normal rendered image
  , _wlFullImage  :: !Image'      -- ^ Detailed rendered image
  , _wlImportance :: !WindowLineImportance -- ^ Importance of message
  , _wlTimestamp  :: {-# UNPACK #-} !UTCTime
  }

-- | A 'Window' tracks all of the messages and metadata for a particular
-- message buffer.
data Window = Window
  { _winMessages :: ![WindowLine] -- ^ Messages to display, newest first
  , _winUnread   :: !Int          -- ^ Messages added since buffer was visible
  , _winTotal    :: !Int          -- ^ Messages in buffer
  , _winMention  :: !Bool         -- ^ Indicates an important event is unread
  }

-- | Flag for the important of a message being added to a window
data WindowLineImportance
  = WLBoring -- ^ Don't update unread count
  | WLNormal -- ^ Increment unread count
  | WLImportant -- ^ Increment unread count and set important flag
  deriving (Eq, Show)

makeLenses ''Window
makeLenses ''WindowLine

-- | A window with no messages
emptyWindow :: Window
emptyWindow = Window
  { _winMessages = []
  , _winUnread   = 0
  , _winTotal    = 0
  , _winMention  = False
  }

-- | Adds a given line to a window as the newest message. Window's
-- unread count will be updated according to the given importance.
addToWindow :: WindowLine -> Window -> Window
addToWindow !msg !win = Window
    { _winMessages = msg : view winMessages win
    , _winTotal    = view winTotal win + 1
    , _winUnread   = view winUnread win
                   + (if view wlImportance msg == WLBoring then 0 else 1)
    , _winMention  = view winMention win
                  || view wlImportance msg == WLImportant
    }

-- | Update the window clearing the unread count and important flag.
windowSeen :: Window -> Window
windowSeen = set winUnread 0
           . set winMention False
