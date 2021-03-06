{-# Language BangPatterns #-}
{-|
Module      : Client.View.Mentions
Description : Mentions view
Copyright   : (c) Eric Mertens, 2016
License     : ISC
Maintainer  : emertens@gmail.com

This module provides the lines that have been highlighted
across the client in sorted order.

-}
module Client.View.Mentions
  ( mentionsViewLines
  ) where

import           Client.Configuration (PaddingMode, configNickPadding)
import           Client.Image.Message
import           Client.Image.PackedImage
import           Client.Image.Palette (Palette)
import           Client.Image.StatusLine
import           Client.State
import           Client.State.Focus
import           Client.State.Window
import           Control.Lens
import qualified Data.Map as Map
import           Data.Time (UTCTime)

-- | Generate the list of message lines marked important ordered by
-- time. Each run of lines from the same channel will be grouped
-- together. Messages are headed by their window, network, and channel.
mentionsViewLines :: Int -> ClientState -> [Image']
mentionsViewLines w st = addMarkers w st entries

  where
    names = clientWindowNames st ++ repeat '?'

    detail = view clientDetailView st

    padAmt = view (clientConfig . configNickPadding) st
    palette = clientPalette st

    entries = merge
              [windowEntries palette w padAmt detail n focus v
              | (n,(focus, v))
                <- names `zip` Map.toList (view clientWindows st) ]

data MentionLine = MentionLine
  { mlTimestamp  :: UTCTime  -- ^ message timestamp for sorting
  , mlWindowName :: Char     -- ^ window names shortcut
  , mlFocus      :: Focus    -- ^ associated window
  , mlImage      :: [Image'] -- ^ wrapped rendered lines
  }

-- | Insert channel name markers between messages from different channels
addMarkers ::
  Int           {- ^ draw width                        -} ->
  ClientState   {- ^ client state                      -} ->
  [MentionLine] {- ^ list of mentions in time order    -} ->
  [Image']      {- ^ mention images and channel labels -}
addMarkers _ _ [] = []
addMarkers w !st (!ml : xs)
  = concatMap mlImage (ml:same)
 ++ minorStatusLineImage (mlFocus ml) w False st
  : addMarkers w st rest
  where
    isSame ml' = mlFocus ml == mlFocus ml'

    (same,rest) = span isSame xs

windowEntries ::
  Palette     {- ^ palette       -} ->
  Int         {- ^ draw columns  -} ->
  PaddingMode {- ^ nick padding  -} ->
  Bool        {- ^ detailed view -} ->
  Char        {- ^ window name   -} ->
  Focus       {- ^ window focus  -} ->
  Window      {- ^ window        -} ->
  [MentionLine]
windowEntries palette w padAmt detailed name focus win =
  [ MentionLine
      { mlTimestamp  = views wlTimestamp unpackUTCTime l
      , mlWindowName = name
      , mlFocus      = focus
      , mlImage      = if detailed
                        then [view wlFullImage l]
                        else drawWindowLine palette w padAmt l
      }
  | let p x = WLImportant == view wlImportance x
  , l <- toListOf (winMessages . each . filtered p) win
  ]

-- | Merge a list of sorted lists of mention lines into a single sorted list
-- in descending order.
merge :: [[MentionLine]] -> [MentionLine]
merge []  = []
merge [x] = x
merge xss = merge (merge2s xss)

merge2s :: [[MentionLine]] -> [[MentionLine]]
merge2s (x:y:z) = merge2 x y : merge2s z
merge2s xs      = xs

merge2 :: [MentionLine] -> [MentionLine] -> [MentionLine]
merge2 [] ys = ys
merge2 xs [] = xs
merge2 xxs@(x:xs) yys@(y:ys)
  | mlTimestamp x >= mlTimestamp y = x : merge2 xs yys
  | otherwise                      = y : merge2 xxs ys
