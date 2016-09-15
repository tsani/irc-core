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

import           Client.Image.PackedImage
import           Client.Image.StatusLine
import           Client.State
import           Client.State.Focus
import           Client.State.Window
import qualified Data.Map as Map
import           Control.Lens
import           Data.Time (UTCTime)
import           Graphics.Vty.Image

-- | Generate the list of message lines marked important ordered by
-- time. Each run of lines from the same channel will be grouped
-- together. Messages are headed by their window, network, and channel.
mentionsViewLines :: ClientState -> [Image]
mentionsViewLines st = addMarkers st entries

  where
    names = clientWindowNames st ++ repeat '?'

    detail = view clientDetailView st

    entries = merge
              [windowEntries detail n focus v
              | (n,(focus, v))
                <- names `zip` Map.toList (view clientWindows st) ]

data MentionLine = MentionLine
  { mlTimestamp  :: UTCTime
  , mlWindowName :: Char
  , mlFocus      :: Focus
  , mlImage      :: Image
  }

addMarkers ::
  ClientState   {- ^ client state                      -} ->
  [MentionLine] {- ^ list of mentions in time order    -} ->
  [Image]       {- ^ mention images and channel labels -}
addMarkers _ [] = []
addMarkers !st (!ml : xs)
  = map mlImage (ml:same)
 ++ minorStatusLineImage (mlFocus ml) st
  : addMarkers st rest
  where
    isSame ml' = mlFocus ml == mlFocus ml'

    (same,rest) = span isSame xs

windowEntries ::
  Bool   {- ^ detailed view -} ->
  Char   {- ^ window name   -} ->
  Focus  {- ^ window focus  -} ->
  Window {- ^ window        -} ->
  [MentionLine]
windowEntries !detailed name focus w =
  [ MentionLine
      { mlTimestamp  = view wlTimestamp l
      , mlWindowName = name
      , mlFocus      = focus
      , mlImage      = unpackImage (if detailed then view wlFullImage l else view wlImage l)
      }
  | l <- view winMessages w
  , WLImportant == view wlImportance l
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
