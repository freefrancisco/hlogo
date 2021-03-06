{-# LANGUAGE CPP, FlexibleInstances, FlexibleContexts, TypeFamilies #-}
{-# OPTIONS_HADDOCK show-extensions #-}
-- | 
-- Module      :  Language.Logo.Prim
-- Copyright   :  (c) 2013-2016, the HLogo team
-- License     :  BSD3
-- Maintainer  :  Nikolaos Bezirgiannis <bezirgia@cwi.nl>
-- Stability   :  experimental
--
-- This module tries to provide an API to the standard library of NetLogo:
-- <http://ccl.northwestern.edu/netlogo/docs/dictionary.html>
module Language.Logo.Prim (
                            -- * Agent related
                            self, myself, other, count, nobody, towards, allp, at_points, towardsxy, in_cone, every, wait, carefully, die, 

                            -- * Turtle related
                            turtles_here, turtles_at, turtles_on, jump, setxy, forward, fd, back, bk, turtles, turtle, turtle_set, face, xcor, set_breed, with_breed, set_color, with_color, set_label_color, with_label_color, with_label, set_xcor, heading, set_heading, with_heading,  ycor, set_ycor, who, color, breed, dx, dy, home, right, rt, left, lt, downhill, downhill4, hide_turtle, ht, show_turtle, st, pen_down, pd, pen_up, pu, pen_erase, pe, no_turtles, hatch, set_size, with_size, with_shape, can_movep,

                            -- * Patch related
                            patch_at, patch_here, patch_ahead, patches, patch, patch_set, no_patches, pxcor, pycor, pcolor, plabel, neighbors, neighbors4, set_plabel, with_plabel, set_pcolor, with_pcolor, with_plabel_color, 

                            -- * Link related
                            hide_link, show_link, link_length, link, links, my_links, my_out_links, my_in_links, no_links, tie, untie, link_set, end1, end2, is_directed_linkp, is_undirected_linkp,

                            -- * Random related
                            random_xcor, random_ycor, random_pxcor, random_pycor, random, random_float, new_seed, random_seed, random_exponential, random_gamma, random_normal, random_poisson,

                            -- * Color
                            black, white, gray, red, orange, brown, yellow, green, lime, turquoise, cyan, sky, blue, violet, magenta, pink, scale_color, extract_rgb, approximate_rgb,

                            -- * List related
                            sum, anyp, item, one_of, min_one_of, max_one_of, remove, remove_item, replace_item, shuffle, sublist, substring, n_of, butfirst, butlast, emptyp, first, foreach, fput, last, length, list, lput, map, memberp, position, reduce, remove_duplicates, reverse, sentence, sort_, sort_by, sort_on, max_, min_,n_values, word,

                            -- * Math
                            xor, e, exp, pi, cos_, sin_, tan_, mod_, acos_, asin_, atan_, int, log_, ln, mean, median, modes, variance, standard_deviation, subtract_headings, abs_, floor, ceiling, remainder, round, sqrt,

                            -- * Misc
                            patch_size, max_pxcor, max_pycor, min_pxcor, min_pycor, world_width, world_height, clear_all_plots, clear_drawing, cd, clear_output, clear_turtles, ct, clear_patches, cp, clear_links, clear_ticks, reset_ticks, tick, tick_advance, ticks, histogram, repeat_, report, loop, stop, while, stats_stm,

                            -- * Input/Output
                            show, print, read_from_string, timer, reset_timer,

                            -- * IO Operations
                            atomic, ask, of_, snapshot, 

                            -- * move_to & Internal (needed for Keyword module)
                            TurtlePatch (..), STMorIO, readTVarSI, splitCapabilities
 ) where

import Prelude hiding (show,print, length)
import qualified Prelude (show, print, length)
import Language.Logo.Base
import Language.Logo.Core
import Language.Logo.CmdOpt
import Language.Logo.Exception

import Control.Monad.Trans.Class (lift)
import qualified Control.Monad.Trans.Reader as Reader
import qualified Data.IntMap.Strict as IM
import qualified Data.Map.Strict as M
import qualified Data.Vector as V
import Data.List (delete, nub,nubBy, find, sort, sortBy, foldl')
import Control.Monad (forM_, liftM, filterM, forever, when, (<=<))
import Data.Word (Word8)
import qualified Data.Foldable as F (Foldable, toList, foldl', foldr, foldlM, mapM_)
import qualified Data.Traversable as T (mapM)
import Data.Maybe (fromMaybe, catMaybes)

-- concurrency
import Control.Concurrent.STM
import GHC.Conc.Sync (unsafeIOToSTM)
import GHC.Conc (numCapabilities)
import Control.Concurrent (threadDelay)
import qualified Control.Concurrent.Thread as Thread (forkOn, result)
import qualified Control.Concurrent.Thread.Group as ThreadG (forkOn, new, wait)
import Data.IORef (writeIORef, readIORef, modifyIORef', newIORef)


-- for rng
import System.Random (randomR)
import qualified System.Random.SplitMix as SM (SMGen, splitSMGen, mkSMGen)
import System.CPUTime (getCPUTime)
import Data.Time.Clock ( getCurrentTime, UTCTime(..), diffUTCTime)
import Data.Ratio (numerator, denominator)

-- For diagrams
import qualified Diagrams.Prelude as Diag
import Diagrams.Backend.Postscript
import Data.Colour.SRGB (sRGB24)

#if __GLASGOW_HASKELL__ < 710
import Control.Applicative ((<$>),(<*>))
#endif

#ifdef STATS_STM
import System.IO.Unsafe (unsafePerformIO)
import Data.Atomics.Counter (newCounter,incrCounter_, readCounter)
{-# NOINLINE counterSTMLoops #-}
-- | Internal
counterSTMLoops = unsafePerformIO $ newCounter 0
{-# NOINLINE counterSTMCommits #-}
-- | Internal
counterSTMCommits = unsafePerformIO $ newCounter 0
#endif

#define todo assert False undefined

{-# SPECIALIZE  self :: C s _s' STM s #-}
{-# SPECIALIZE  self :: C s _s' IO s #-}
-- |  Reports this turtle or patch. 
self :: STMorIO m => C s _s' m s -- ^ returns a list (set) of agentrefs to be compatible with the 'turtle-set' function
self = do
  (s,_,_) <- Reader.ask
  return s

{-# SPECIALIZE  myself :: C s s' STM s' #-}
{-# SPECIALIZE  myself :: C s s' IO s' #-}
-- | "self" and "myself" are very different. "self" is simple; it means "me". "myself" means "the turtle or patch who asked me to do what I'm doing right now."
-- When an agent has been asked to run some code, using myself in that code reports the agent (turtle or patch) that did the asking. 
-- NB: Implemented for ask, of, with
myself :: STMorIO m => C s s' m s'
myself = do
  (_,m,_) <- Reader.ask
  return m

{-# SPECIALIZE INLINE other :: Eq s => [s] -> C s _s' STM [s] #-}
{-# SPECIALIZE INLINE other :: Eq s => [s] -> C s _s' IO [s] #-}
{-# WARNING other "TODO: not yet working for the new specialized agentsets" #-}
-- |  Reports an agentset which is the same as the input agentset but omits this agent. 
other :: (STMorIO m, Eq s) => [s] -> C s _s' m [s]
other as = do
  s <- self
  return $ delete s as


{-# SPECIALIZE INLINE  patches :: C _s _s' STM Patches #-}
{-# SPECIALIZE INLINE  patches :: C _s _s' IO Patches #-}
-- | Reports the agentset consisting of all patches. 
patches :: STMorIO m => C _s _s' m Patches
patches = return __patches 

{-# SPECIALIZE INLINE patch :: Double -> Double -> C _s _s' STM Patch #-}
{-# SPECIALIZE INLINE patch :: Double -> Double -> C _s _s' IO Patch #-}
-- | Given the x and y coordinates of a point, reports the patch containing that point. 
patch :: STMorIO m => Double -> Double -> C _s _s' m Patch
patch x y = maybe nobody return $ patch' x y

{-# INLINE patch' #-}
patch' :: Double -> Double -> Maybe Patch
patch' x y = let mix = min_pxcor_ cmdOpt
                 miy = min_pycor_ cmdOpt
                 max = max_pxcor_ cmdOpt
                 may = max_pycor_ cmdOpt
                 norm_x = if horizontal_wrap_ cmdOpt then ((round x + max) `mod` (max-mix+1)) + mix else round x
                 norm_y = if vertical_wrap_ cmdOpt then ((round y + may) `mod` (may-miy+1)) + miy else round y
             in if mix <= norm_x && norm_x <= max && miy <= norm_y && norm_y <= may
                then Just $ __patches `V.unsafeIndex` (((norm_x-mix)*(may-miy+1))+(norm_y-miy))
                else Nothing -- i cannot put nobody here because this function is pure
    
{-# WARNING carefully "TODO" #-}
-- | Runs commands1. If a runtime error occurs inside commands1, NetLogo won't stop and alert the user that an error occurred. It will suppress the error and run commands2 instead. 
carefully :: C _s _s' STM a -> C _s _s' STM a -> C _s _s' STM a
carefully c c' = catch c (\ ex -> let _ = (ex :: SomeException) in c')

{-# SPECIALIZE  patch_at :: TurtlePatch s => Double -> Double -> C s _s' STM Patch #-}
{-# SPECIALIZE  patch_at :: TurtlePatch s => Double -> Double -> C s _s' IO Patch #-}
-- | Reports the patch at (dx, dy) from the caller, that is, the patch containing the point dx east and dy patches north of this agent. 
patch_at :: (STMorIO m, TurtlePatch s) => Double -> Double -> C s _s' m Patch
patch_at x y = do
  (s,_,_) <- Reader.ask
  (MkPatch {pxcor_ = px, pycor_=py}) <- patch_on_ s
  maybe nobody return $ patch' (fromIntegral px + x) (fromIntegral py +y)

{-# SPECIALIZE  patch_ahead :: Double -> C Turtle _s' STM Patch #-}
{-# SPECIALIZE  patch_ahead :: Double -> C Turtle _s' IO Patch #-}
-- | Reports the single patch that is the given distance "ahead" of this turtle, that is, along the turtle's current heading. 
patch_ahead :: STMorIO m => Double -> C Turtle _s' m Patch
patch_ahead n = do
  x <- xcor 
  y <- ycor
  dx_ <- dx
  dy_ <- dy
  let max = max_pxcor_ cmdOpt
  let may = max_pycor_ cmdOpt
  let mix = min_pxcor_ cmdOpt
  let miy = min_pycor_ cmdOpt
  let px_new = (fromIntegral (round x :: Int) :: Double) + if horizontal_wrap_ cmdOpt
                                                         then (dx_*n + fromIntegral max) `mod_` (max - mix + 1) + fromIntegral mix
                                                         else dx_*n

  let py_new = (fromIntegral (round y :: Int) :: Double) + if vertical_wrap_ cmdOpt
                                                         then (dy_*n + fromIntegral may) `mod_` (may - miy + 1) + fromIntegral miy
                                                         else  dy_*n
  maybe nobody return $ patch' px_new py_new

{-# INLINE black #-}
black :: Double
black = 0
{-# INLINE white #-}
white :: Double
white = 9.9
{-# INLINE gray #-}
gray :: Double
gray = 5
{-# INLINE red #-}
red :: Double
red = 15
{-# INLINE orange #-}
orange :: Double
orange = 25
{-# INLINE brown #-}
brown :: Double
brown = 35
{-# INLINE yellow #-}
yellow :: Double
yellow = 45
{-# INLINE green #-}
green :: Double
green = 55
{-# INLINE lime #-}
lime :: Double
lime = 65
{-# INLINE turquoise #-}
turquoise :: Double
turquoise = 75
{-# INLINE cyan #-}
cyan :: Double
cyan = 85
{-# INLINE sky #-}
sky :: Double
sky = 95
{-# INLINE blue #-}
blue :: Double
blue = 105
{-# INLINE violet #-}
violet :: Double
violet = 115
{-# INLINE magenta #-}
magenta :: Double
magenta = 125
{-# INLINE pink #-}
pink :: Double
pink = 135

{-# SPECIALIZE INLINE count :: Patches -> C _s _s' STM Int #-}
{-# SPECIALIZE INLINE count :: Patches -> C _s _s' IO Int #-}
{-# SPECIALIZE INLINE count :: Turtles -> C _s _s' STM Int #-}
{-# SPECIALIZE INLINE count :: Turtles -> C _s _s' IO Int #-}
{-# SPECIALIZE INLINE count :: Links -> C _s _s' STM Int #-}
{-# SPECIALIZE INLINE count :: Links -> C _s _s' IO Int #-}
-- | Reports the number of agents in the given agentset. 
count :: (STMorIO m, F.Foldable t) => t a -> C _s _s' m Int
-- count [Nobody] = throw $ TypeException "agent" Nobody
#if __GLASGOW_HASKELL__ < 710
count = return . F.foldl' (\c _ -> c+1) 0
#else
count = return . Prelude.length
#endif



{-# SPECIALIZE INLINE anyp :: Patches -> C _s _s' STM Bool #-}
{-# SPECIALIZE INLINE anyp :: Patches -> C _s _s' IO Bool #-}
{-# SPECIALIZE INLINE anyp :: Turtles -> C _s _s' STM Bool #-}
{-# SPECIALIZE INLINE anyp :: Turtles -> C _s _s' IO Bool #-}
{-# SPECIALIZE INLINE anyp :: Links -> C _s _s' STM Bool #-}
{-# SPECIALIZE INLINE anyp :: Links -> C _s _s' IO Bool #-}
-- | Reports true if the given agentset is non-empty, false otherwise. 
anyp :: (STMorIO m, F.Foldable t) => t a -> C _s _s' m Bool
-- anyp [Nobody] = throw $ TypeException "agent" Nobody
#if __GLASGOW_HASKELL__ < 710
anyp = return . F.foldr (\_ _ -> True) False
#else
anyp = pure . not . Prelude.null
#endif

allp :: (F.Foldable t, Agent (t a)) => C (One (t a)) p IO Bool -> t a -> C p p' IO Bool
allp r as = todo
-- do
--   res <- with r as
--   return $ Prelude.length as == Prelude.length res

{-# INLINE length #-}
length :: (STMorIO m) => [a] -> C _s _s' m Int
length = return . Prelude.length

-- | The turtle moves forward by number units all at once (rather than one step at a time as with the forward command). 
jump :: Double -> C Turtle _s' STM ()
jump n = do
   (MkTurtle {xcor_ = tx, ycor_ = ty, heading_ = th}, _,_) <- Reader.ask
   lift $ do
       h <- readTVar th
       x' <- liftM ((sin_ h * n) +) $ readTVar tx
       y' <- liftM ((cos_ h * n) +) $ readTVar ty
       let max_x = max_pxcor_ cmdOpt
           dmax_x = fromIntegral max_x
           min_x = min_pxcor_ cmdOpt
           dmin_x = fromIntegral min_x
           max_y = max_pycor_ cmdOpt
           dmax_y = fromIntegral max_y
           min_y = min_pycor_ cmdOpt
           dmin_y = fromIntegral min_y
       if horizontal_wrap_ cmdOpt
         then
           writeTVar tx $! ((x' + dmax_x) `mod_` (max_x - min_x +1)) + dmin_x
         else
           when (dmin_x -0.5 < x' && x' < dmax_x + 0.5) $ writeTVar tx $! x'
       if vertical_wrap_ cmdOpt
         then
             writeTVar ty $! ((y' + dmax_y) `mod_` (max_y - min_y +1)) + dmin_y
         else
           when (dmin_y -0.5  < y' && y' < dmax_y + 0.5) $ writeTVar ty $! y'


-- | The turtle sets its x-coordinate to x and its y-coordinate to y. 
setxy :: Double -> Double -> C Turtle _s' STM ()
setxy x' y' = do
    (MkTurtle {xcor_ = tx, ycor_ = ty},_,_) <- Reader.ask
    let max_x = max_pxcor_ cmdOpt
    let dmax_x = fromIntegral max_x
    let min_x = min_pxcor_ cmdOpt
    let dmin_x = fromIntegral min_x
    let max_y = max_pycor_ cmdOpt
    let dmax_y = fromIntegral max_y
    let min_y = min_pycor_ cmdOpt
    let dmin_y = fromIntegral min_y
    if horizontal_wrap_ cmdOpt
      then
        lift $ writeTVar tx $! ((x' + dmax_x) `mod_` (max_x - min_x +1)) + dmin_x
      else
          if dmin_x -0.5 < x' && x' < dmax_x + 0.5
          then lift $ writeTVar tx $! x'
          else error "wrap"
    if vertical_wrap_ cmdOpt
      then
          lift $ writeTVar ty $! ((y' + dmax_y) `mod_` (max_y - min_y +1)) + dmin_y
      else
          if dmin_y -0.5  < y' && y' < dmax_y + 0.5
          then lift $ writeTVar ty $! y'
          else error "wrap"


-- | The turtle moves forward by number steps, one step at a time. (If number is negative, the turtle moves backward.) 
forward :: Double -> C Turtle _s' STM ()
forward n | n > 1 = jump 1 >> forward (n-1)
          | n < -1 = jump (-1) >> forward (n+1)
          | otherwise = jump n
 
{-# INLINE fd #-}
-- | alias for 'forward'
fd :: Double -> C Turtle _s' STM ()
fd = forward

-- | The turtle moves backward by number steps. (If number is negative, the turtle moves forward.) 
{-# INLINE back #-}
back :: Double -> C Turtle _s' STM ()
back n = forward (-n)
{-# INLINE bk #-}
-- | alias for 'back'
bk :: Double -> C Turtle _s' STM ()
bk = back

-- | As it is right now, if an agent holds a past reference to a turtle, it can still modify it and ask it to do sth. 
-- The only guarantee is that the __next__ 'turtles','turtles_at','turtles_here','turtles_on'... etc
-- will not return this dead agent.

instance TurtleLink Turtle where
    breed_ = tbreed_
    shape_ = tshape_
    label_ = tlabel_
    label_color_ = tlabel_color_
    color_ = tcolor_
    die = do
      (MkTurtle {who_ = tw},_,_) <- Reader.ask
      lift $ modifyTVar' __turtles (IM.delete tw)

instance TurtleLink Link where
    breed_ = lbreed_
    shape_ = lshape_
    label_ = llabel_
    label_color_ = llabel_color_
    color_ = lcolor_
    die = do
      (MkLink {end1_ = e1, end2_ = e2, directed_ = d}, _,_) <- Reader.ask
      lift $ modifyTVar' __links (M.delete (e1,e2) . 
                                           (if d -- is directed
                                            then id
                                            else M.delete (e2,e1)
                                           ))
class Agent s => TurtlePatch s where
    patch_on_ :: STMorIO m => s -> C s _s' m Patch
    -- | The turtle sets its x and y coordinates to be the same as the given agent's.
    -- (If that agent is a patch, the effect is to move the turtle to the center of that patch.) 
    move_to :: s -> C Turtle _s' STM ()

instance TurtlePatch Patch where
    patch_on_ = return
    move_to (MkPatch {pxcor_ = x, pycor_ = y}) = do
      set_xcor (fromIntegral x)
      set_ycor (fromIntegral y)

instance TurtlePatch Turtle where
    patch_on_ (MkTurtle {xcor_=tx,ycor_=ty}) = do
                 x <- readTVarSI tx
                 y <- readTVarSI ty
                 patch x y
    move_to (MkTurtle {xcor_=tx,ycor_=ty}) = do
                 x <- lift $ readTVar tx
                 set_xcor x
                 y <- lift $ readTVar ty
                 set_ycor y

{-# SPECIALIZE  patch_on_ :: TurtlePatch s => s -> C s _s' IO Patch #-}
{-# SPECIALIZE  patch_on_ :: TurtlePatch s => s -> C s _s' STM Patch #-}


{-# SPECIALIZE  turtle_set :: [C _s _s' STM Turtle] -> C _s _s' STM Turtles #-}
{-# SPECIALIZE  turtle_set :: [C _s _s' IO Turtle] -> C _s _s' IO Turtles #-}



-- | Reports an agentset containing all of the turtles anywhere in any of the inputs.
--  NB: HLogo no support for nested turtle_set concatenation/flattening
turtle_set :: STMorIO m => [C _s _s' m Turtle] -> C _s _s' m Turtles
turtle_set = liftM (foldr (\ t@(MkTurtle {who_=w}) acc -> 
                                  -- if x == Nobody -- filter Nobody
                                  -- then acc
                                  -- else case x of -- type check
                                  --        TurtleRef _ _ -> 
                                  IM.insert w t acc
                                         -- _ -> throw $ TypeException "turtle" x
                          ) IM.empty) . sequence

{-# SPECIALIZE  patch_set :: [C _s _s' STM Patch] -> C _s _s' STM Patches #-}
{-# SPECIALIZE  patch_set :: [C _s _s' IO Patch] -> C _s _s' IO Patches #-}
-- | Reports an agentset containing all of the patches anywhere in any of the inputs.
--  NB: HLogo no support for nested patch_set concatenation/flattening
patch_set :: STMorIO m => [C _s _s' m Patch] -> C _s _s' m Patches
patch_set = liftM V.fromList . sequence

{-# SPECIALIZE  link_set :: [C _s _s' STM Link] -> C _s _s' STM Links #-}
{-# SPECIALIZE  link_set :: [C _s _s' IO Link] -> C _s _s' IO Links #-}
-- | Reports an agentset containing all of the links anywhere in any of the inputs.
--  NB: HLogo no support for nested turtle_set concatenation/flattening
link_set :: STMorIO m => [C _s _s' m Link] -> C _s _s' m Links
link_set = liftM (foldr (\ l@(MkLink {end1_=f,end2_=t}) acc -> -- if x == Nobody -- filter Nobody
                                      -- then acc
                                      -- else case x of -- type check
                                      --        LinkRef _ _ -> 
                                 M.insert (f,t) l acc
                                             -- _ -> throw $ TypeException "link" x
                        ) M.empty) . sequence


{-# WARNING can_movep "TODO: test it" #-}
{-# SPECIALIZE can_movep :: Double -> C Turtle _s' STM Bool #-}
{-# SPECIALIZE can_movep :: Double -> C Turtle _s' IO Bool #-}
-- | Reports true if this turtle can move distance in the direction it is facing without violating the topology; reports false otherwise. 
can_movep :: STMorIO m => Double -> C Turtle _s' m Bool
can_movep n = do
  x <- xcor 
  y <- ycor
  dx_ <- dx
  dy_ <- dy
  let max = max_pxcor_ cmdOpt
  let may = max_pycor_ cmdOpt
  let mix = min_pxcor_ cmdOpt
  let miy = min_pycor_ cmdOpt
  let px_new = round $ x + if horizontal_wrap_ cmdOpt
                           then (dx_*n + fromIntegral max) `mod_` (max - mix + 1) + fromIntegral mix
                           else dx_*n
  let py_new = round $ y + if vertical_wrap_ cmdOpt
                           then (dy_*n + fromIntegral may) `mod_` (may - miy + 1) + fromIntegral miy
                           else  dy_*n
  return (not (not (horizontal_wrap_ cmdOpt) && (px_new > max || px_new < min_pxcor_ cmdOpt)) 
       || (not (vertical_wrap_ cmdOpt) && (py_new > may || py_new < min_pycor_ cmdOpt)))

set_heading :: Double -> C Turtle _s' STM ()
set_heading v = do
  (t,_,_) <- Reader.ask
  lift $ writeTVar (heading_ t) $! v

{-# SPECIALIZE  pxcor :: TurtlePatch s => C s _s' STM Int #-}
{-# SPECIALIZE  pxcor :: TurtlePatch s => C s _s' IO Int #-}
-- |These are built-in patch variables. They hold the x and y coordinate of the patch. They are always integers. You cannot set these variables, because patches don't move 
pxcor :: (TurtlePatch s, STMorIO m) => C s _s' m Int
pxcor = do
  (s,_,_) <- Reader.ask
  liftM pxcor_ $ patch_on_ s

{-# SPECIALIZE  pycor :: TurtlePatch s => C s _s' STM Int #-}
{-# SPECIALIZE  pycor :: TurtlePatch s => C s _s' IO Int #-}
-- | These are built-in patch variables. They hold the x and y coordinate of the patch. They are always integers. You cannot set these variables, because patches don't mov 
pycor :: (TurtlePatch s, STMorIO m) => C s _s' m Int
pycor = do
  (s,_,_) <- Reader.ask
  liftM pycor_ $ patch_on_ s

{-# SPECIALIZE  set_plabel :: String -> C Turtle _s' STM () #-}
{-# SPECIALIZE  set_plabel :: String -> C Patch _s' STM () #-}
set_plabel :: TurtlePatch s => String -> C s _s' STM ()
set_plabel l = do
  (s,_,_) <- Reader.ask
  MkPatch {plabel_ = tl} <- patch_on_ s
  lift $ writeTVar tl $! l

{-# SPECIALIZE  set_pcolor :: Double -> C Turtle _s' STM () #-}
{-# SPECIALIZE  set_pcolor :: Double -> C Patch _s' STM () #-}
set_pcolor :: TurtlePatch s => Double -> C s _s' STM ()
set_pcolor c = do
  (s,_,_) <- Reader.ask
  MkPatch {pcolor_ = tc} <- patch_on_ s
  lift $ writeTVar tc $! c

{-# SPECIALIZE  set_breed :: String -> C Turtle _s' STM () #-}
{-# SPECIALIZE  set_breed :: String -> C Link _s' STM () #-}
set_breed :: TurtleLink s => String -> C s _s' STM ()
set_breed v = do
  (s,_,_) <- Reader.ask
  lift $ writeTVar (breed_ s) $! v

{-# SPECIALIZE  set_color :: Double -> C Turtle _s' STM () #-}
{-# SPECIALIZE  set_color :: Double -> C Link _s' STM () #-}
set_color :: TurtleLink s => Double -> C s _s' STM ()
set_color v = do
  (s,_,_) <- Reader.ask
  lift $ writeTVar (color_ s) $! v

{-# SPECIALIZE  set_label_color :: Double -> C Turtle _s' STM () #-}
{-# SPECIALIZE   set_label_color :: Double -> C Link _s' STM () #-}
set_label_color :: TurtleLink s => Double -> C s _s' STM ()
set_label_color v = do
  (s,_,_) <- Reader.ask
  lift $ writeTVar (label_color_ s) $! v

set_xcor :: Double -> C Turtle _s' STM ()
set_xcor x' = do
    (MkTurtle {xcor_ = tx},_,_) <- Reader.ask
    let max_x = max_pxcor_ cmdOpt
    let dmax_x = fromIntegral max_x
    let min_x = min_pxcor_ cmdOpt
    let dmin_x = fromIntegral min_x
    if horizontal_wrap_ cmdOpt
     then
         lift $ writeTVar tx $! ((x' + dmax_x) `mod_` (max_x - min_x +1)) + dmin_x
     else
         if dmin_x -0.5 < x' && x' < dmax_x + 0.5
         then lift $ writeTVar tx $! x'
         else error "wrap"


set_size :: Double -> C Turtle _s' STM ()
set_size v = do
  (t,_,_) <- Reader.ask
  lift $ writeTVar (size_ t) $! v

set_ycor :: Double -> C Turtle _s' STM ()
set_ycor y' = do
   (MkTurtle {ycor_ = ty},_,_) <- Reader.ask
   let max_y = max_pycor_ cmdOpt
   let dmax_y = fromIntegral max_y
   let min_y = min_pycor_ cmdOpt
   let dmin_y = fromIntegral min_y
   if vertical_wrap_ cmdOpt
     then
         lift $ writeTVar ty $! ((y' + dmax_y) `mod_` (max_y - min_y +1)) + dmin_y
     else
         if dmin_y -0.5 < y' && y' < dmax_y + 0.5
         then lift $ writeTVar ty $! y'
         else error "wrap"
 
{-# SPECIALIZE  who :: C Turtle _s' STM Int #-}
{-# SPECIALIZE  who :: C Turtle _s' IO Int #-}
-- | This is a built-in turtle variable. It holds the turtle's "who number" or ID number, an integer greater than or equal to zero. You cannot set this variable; a turtle's who number never changes. 
who :: STMorIO m => C Turtle _s' m Int
who = do
  (MkTurtle {who_=tw},_,_) <- Reader.ask
  return tw


{-# SPECIALIZE  dx :: C Turtle _s' STM Double #-}
{-# SPECIALIZE  dx :: C Turtle _s' IO Double #-}
-- | Reports the x-increment (the amount by which the turtle's xcor would change) if the turtle were to take one step forward in its current heading. 
dx :: STMorIO m => C Turtle _s' m Double
dx = liftM sin_ $ heading

{-# SPECIALIZE  dy :: C Turtle _s' STM Double #-}
{-# SPECIALIZE  dy :: C Turtle _s' IO Double #-}
-- | Reports the y-increment (the amount by which the turtle's ycor would change) if the turtle were to take one step forward in its current heading. 
dy :: STMorIO m => C Turtle _s' m Double
dy = liftM cos_ $ heading

-- | Reports a number suitable for seeding the random number generator.
-- The numbers reported by new-seed are based on the current date and time in milliseconds. 
-- Unlike NetLogo's new-seed, HLogo may report the same number twice in succession.
--
-- NB: taken from Haskell's random library
new_seed :: C _s _s' STM Int
new_seed = do
    cpt <- lift $ unsafeIOToSTM getCPUTime
    (sec, psec) <- lift $ unsafeIOToSTM getTime
    return $ fromIntegral (sec * 12345 + psec + cpt)
        where
          getTime :: IO (Integer, Integer)
          getTime = do
             utc <- getCurrentTime
             let daytime = toRational $ utctDayTime utc
             return $ numerator daytime `quotRem` denominator daytime

random_seed :: Int -> C s _s' IO ()
random_seed i = do
  (_,_,tgen) <-Reader.ask
  lift $ writeIORef tgen $! SM.mkSMGen $ fromIntegral i
                
-- | Reports a random floating point number from the allowable range of turtle coordinates along the given axis, x . 
random_xcor :: C s _s' IO Double
random_xcor = do
  (_,_,tgen) <-Reader.ask
  gen <- lift $ readIORef tgen
  let (v, gen') = randomR (fromIntegral (min_pxcor_ cmdOpt) :: Double, fromIntegral $ max_pxcor_ cmdOpt) gen
  lift $ writeIORef tgen $! gen'
  return v

-- | Reports a random floating point number from the allowable range of turtle coordinates along the given axis, y. 
random_ycor :: C s _s' IO Double
random_ycor = do
  (_,_,tgen) <-Reader.ask
  gen <- lift $ readIORef tgen
  let (v, gen') = randomR (fromIntegral (min_pycor_ cmdOpt) :: Double, fromIntegral $ max_pycor_ cmdOpt) gen
  lift $ writeIORef tgen $! gen'
  return v

-- | Reports a random integer ranging from min-pxcor to max-pxcor inclusive. 
random_pxcor :: C s _s' IO Int
random_pxcor = do
  (_,_,tgen) <-Reader.ask
  gen <- lift $ readIORef tgen
  let (v, gen') = randomR (min_pxcor_ cmdOpt, max_pxcor_ cmdOpt) gen
  lift $ writeIORef tgen $! gen'
  return v

-- | Reports a random integer ranging from min-pycor to max-pycor inclusive. 
random_pycor :: C s _s' IO Int
random_pycor = do
  (_,_,tgen) <-Reader.ask
  gen <- lift $ readIORef tgen
  let (v, gen') = randomR (min_pycor_ cmdOpt, max_pycor_ cmdOpt) gen
  lift $ writeIORef tgen $! gen'
  return v

{-# WARNING random "maybe it can become faster with some small fraction added to the input or subtracted and then floored" #-}
{-# SPECIALIZE random :: (Num b, Real a) => a -> C Observer () IO b #-}
{-# SPECIALIZE random :: (Num b, Real a) => a -> C Turtle _s' IO b #-}
{-# SPECIALIZE random :: (Num b, Real a) => a -> C Patch _s' IO b #-}
{-# SPECIALIZE random :: (Num b, Real a) => a -> C Link _s' IO b #-}
-- | If number is positive, reports a random integer greater than or equal to 0, but strictly less than number.
-- If number is negative, reports a random integer less than or equal to 0, but strictly greater than number.
-- If number is zero, the result is always 0 as well. 
random :: (Num b, Real a) => a -> C s _s' IO b
random x = do
  (_,_,tgen) <- Reader.ask
  gen <- lift $ readIORef tgen
  let (n, f) = properFraction (realToFrac x :: Double)
  let randRange = if n > 0 
                  then (0, if f == 0 
                       then n-1
                       else n)
                  else (if f == 0
                        then n+1
                        else n, 0)
  let (v, gen') = randomR randRange gen
  lift $ writeIORef tgen $! gen'
  return (fromIntegral (v :: Int))

-- |  If number is positive, reports a random floating point number greater than or equal to 0 but strictly less than number.
-- If number is negative, reports a random floating point number less than or equal to 0, but strictly greater than number.
-- If number is zero, the result is always 0. 
random_float :: Double -> C s _s' IO Double
random_float x = do
  (_,_,tgen) <- Reader.ask
  gen <- lift $ readIORef tgen
  let (v, gen') = randomR (if x > 0 then (0,x) else (x,0)) gen
  lift $ writeIORef tgen $! gen'
  return v

{-# WARNING random_exponential "TODO" #-}
-- | random-exponential reports an exponentially distributed random floating point number. 
random_exponential :: t -> t1
random_exponential _m = todo

{-# WARNING random_gamma "TODO" #-}
-- | random-gamma reports a gamma-distributed random floating point number as controlled by the floating point alpha and lambda parameters. 
random_gamma :: t -> t1 -> t2
random_gamma _a _l = todo

{-# WARNING random_normal "TODO" #-}
-- | random-normal reports a normally distributed random floating point number. 
random_normal :: t -> t1 -> t2
random_normal _m _s = todo

{-# WARNING random_poisson "TODO" #-}
-- | random-poisson reports a Poisson-distributed random integer. 
random_poisson :: t -> t1
random_poisson _m = todo


-- | This turtle moves to the origin (0,0). Equivalent to setxy 0 0. 
{-# INLINE home #-}
home :: C Turtle _s' STM ()
home = setxy 0 0

-- | The turtle turns right by number degrees. (If number is negative, it turns left.) 
right :: Double -> C Turtle _s' STM ()
right n = do
  (MkTurtle {heading_=th},_,_) <- Reader.ask
  lift $ modifyTVar' th (\ h -> mod_ (h+n) 360)
{-# INLINE rt #-}
-- | alias for 'right'
rt :: Double -> C Turtle _s' STM ()
rt = right

-- | The turtle turns left by number degrees. (If number is negative, it turns right.) 
{-# INLINE left #-}
left :: Double -> C Turtle _s' STM ()
left n = right (-n)

{-# INLINE lt #-}
-- | alias for 'left'
lt :: Double -> C Turtle _s' STM ()
lt = left

{-# WARNING delta "TODO: there is some problem here, an argument is ignored" #-}
-- | Internal
delta :: (Num a, Ord a) => a -> a -> t -> a
delta a1 a2 _aboundary =
    min (abs (a2 - a1)) (abs (a2 + a1) + 1)


{-# INLINE nobody #-}
-- | This is a special value which some primitives such as turtle, one-of, max-one-of, etc. report to indicate that no agent was found. Also, when a turtle dies, it becomes equal to nobody. 
--
-- It can be returned from all primitives that normally return 1 agent. It can also be returned from a turtle reference that got died or the 'turtle' primitive to a dead agent,, like implicitly nullifying the agent.
nobody :: (STMorIO m, Agent a) => C _s _s' m a
nobody = error "nobody"

{-# WARNING downhill "TODO" #-}
-- | Moves the turtle to the neighboring patch with the lowest value for patch-variable. 
-- If no neighboring patch has a smaller value than the current patch, the turtle stays put. 
-- If there are multiple patches with the same lowest value, the turtle picks one randomly. 
-- Non-numeric values are ignored.
-- downhill considers the eight neighboring patches
downhill :: t
downhill = todo

{-# WARNING downhill4 "TODO" #-}
-- | Moves the turtle to the neighboring patch with the lowest value for patch-variable. 
-- If no neighboring patch has a smaller value than the current patch, the turtle stays put. 
-- If there are multiple patches with the same lowest value, the turtle picks one randomly. 
-- Non-numeric values are ignored.
-- downhill4 only considers the four neighbors. 
downhill4 :: t
downhill4 = todo

-- | Set the caller's heading towards agent. 
{-# INLINE face #-}
face :: TurtlePatch a => a -> C Turtle _s' STM ()
face a = set_heading =<< towards a

{-# WARNING towardsxy "TODO" #-}
-- | Reports the heading from the turtle or patch towards the point (x,y). 
towardsxy :: t
towardsxy = todo


-- | The turtle makes itself invisible. 
hide_turtle :: C Turtle _s' STM ()
hide_turtle = do
  (MkTurtle {hiddenp_ = th},_,_) <- Reader.ask
  lift $ writeTVar th True

{-# INLINE ht #-}
-- | alias for 'hide_turtle'
ht :: C Turtle _s' STM ()
ht = hide_turtle

-- | The turtle becomes visible again. 
show_turtle :: C Turtle _s' STM ()
show_turtle = do
  (MkTurtle {hiddenp_ = th},_,_) <- Reader.ask
  lift $ writeTVar th False

{-# INLINE st #-}
-- | alias for 'show_turtle'
st :: C Turtle _s' STM ()
st = show_turtle

-- | The turtle changes modes between drawing lines, removing lines or neither. 
pen_down :: C Turtle _s' STM ()
pen_down = do
  (MkTurtle {pen_mode_ = tp},_,_) <- Reader.ask
  lift $ writeTVar tp Down

{-# INLINE pd #-}
-- | alias for 'pen_down'
pd :: C Turtle _s' STM ()
pd = pen_down

-- | The turtle changes modes between drawing lines, removing lines or neither. 
pen_up :: C Turtle _s' STM ()
pen_up = do
  (MkTurtle {pen_mode_ = tp},_,_) <- Reader.ask
  lift $ writeTVar tp Up

{-# INLINE pu #-}
-- | alias for 'pen_up'
pu :: C Turtle _s' STM ()
pu = pen_up

pen_erase :: C Turtle _s' STM ()
-- | The turtle changes modes between drawing lines, removing lines or neither. 
pen_erase = do
  (MkTurtle {pen_mode_ = tp},_,_) <- Reader.ask
  lift $ writeTVar tp Erase

{-# INLINE pe #-}
-- | alias for 'pen_erase'
pe :: C Turtle _s' STM ()
pe = pen_erase







-- | This reporter lets you give a turtle a "cone of vision" in front of itself. 
in_cone :: t
in_cone = todo




{-# SPECIALIZE  no_turtles :: C _s _s' STM Turtles #-}
{-# SPECIALIZE  no_turtles :: C _s _s' IO Turtles #-}
-- | Reports an empty turtle agentset. 
no_turtles :: STMorIO m => C _s _s' m Turtles
no_turtles = return IM.empty

{-# SPECIALIZE  no_patches :: C _s _s' STM Patches #-}
{-# SPECIALIZE  no_patches :: C _s _s' IO Patches #-}
-- | Reports an empty patch agentset. 
no_patches :: STMorIO m => C _s _s' m Patches
no_patches = return V.empty

{-# SPECIALIZE  no_links :: C _s _s' STM Links #-}
{-# SPECIALIZE  no_links :: C _s _s' IO Links #-}
-- | Reports an empty link agentset. 
no_links :: STMorIO m => C _s _s' m Links
no_links = return M.empty


-- | Reports true if either boolean1 or boolean2 is true, but not when both are true. 
xor :: Bool -> Bool -> Bool
xor p q = (p || q) && not (p && q)


{-# SPECIALIZE  patch_size :: C _s _s' STM Int #-}
{-# SPECIALIZE  patch_size :: C _s _s' IO Int #-}
patch_size :: STMorIO m => C _s _s' m Int
patch_size = return $ patch_size_ cmdOpt

{-# SPECIALIZE  max_pxcor :: C _s _s' STM Int #-}
{-# SPECIALIZE  max_pxcor :: C _s _s' IO Int #-}
-- | This reporter gives the maximum x-coordinate for patches, which determines the size of the world. 
max_pxcor :: STMorIO m => C _s _s' m Int
max_pxcor = return $ max_pxcor_ cmdOpt

{-# SPECIALIZE  max_pycor :: C _s _s' STM Int #-}
{-# SPECIALIZE  max_pycor :: C _s _s' IO Int #-}
-- | This reporter gives the maximum y-coordinate for patches, which determines the size of the world. 
max_pycor :: STMorIO m => C _s _s' m Int
max_pycor = return $ max_pycor_ cmdOpt

{-# SPECIALIZE  min_pxcor :: C _s _s' STM Int #-}
{-# SPECIALIZE  min_pxcor :: C _s _s' IO Int #-}
-- | This reporter gives the minimum x-coordinate for patches, which determines the size of the world. 
min_pxcor :: STMorIO m => C _s _s' m Int
min_pxcor = return $ min_pxcor_ cmdOpt

{-# SPECIALIZE  min_pycor :: C _s _s' STM Int #-}
{-# SPECIALIZE  min_pycor :: C _s _s' IO Int #-}
-- | This reporter gives the maximum y-coordinate for patches, which determines the size of the world. 
min_pycor :: STMorIO m => C _s _s' m Int
min_pycor = return $ min_pycor_ cmdOpt

{-# SPECIALIZE  world_width :: C _s _s' STM Int #-}
{-# SPECIALIZE  world_width :: C _s _s' IO Int #-}
-- | This reporter gives the total width of the NetLogo world. 
world_width :: STMorIO m => C _s _s' m Int
world_width = return $ max_pxcor_ cmdOpt - min_pxcor_ cmdOpt + 1

{-# SPECIALIZE  world_height :: C _s _s' STM Int #-}
{-# SPECIALIZE  world_height :: C _s _s' IO Int #-}
-- | This reporter gives the total height of the NetLogo world. 
world_height :: STMorIO m => C _s _s' m Int
world_height = return $ max_pycor_ cmdOpt - min_pycor_ cmdOpt + 1


{-# WARNING clear_all_plots "TODO" #-}
-- | Clears every plot in the model.
clear_all_plots :: C Observer () IO ()
clear_all_plots = todo

{-# WARNING clear_drawing "TODO" #-}
-- | Clears all lines and stamps drawn by turtles. 
clear_drawing :: C Observer () IO ()
clear_drawing = todo

{-# INLINE cd #-}
-- | alias for 'clear_drawing'
cd :: C Observer () IO ()
cd = clear_drawing

{-# WARNING clear_output "TODO" #-}
-- | Clears all text from the model's output area, if it has one. Otherwise does nothing. 
clear_output :: C Observer () IO ()
clear_output = todo


-- | Kills all turtles.
-- Also resets the who numbering, so the next turtle created will be turtle 0.
clear_turtles :: C Observer () IO ()
clear_turtles = lift $ atomically $ do
                  writeTVar __turtles IM.empty
                  writeTVar __who 0

{-# INLINE ct #-}
-- | alias for 'clear_turtles'
ct :: C Observer () IO ()
ct = clear_turtles

{-# INLINE clear_links #-}
-- | Kills all links.
clear_links :: C Observer () IO ()
clear_links = lift $ atomically $ writeTVar __links M.empty

-- | Clears the patches by resetting all patch variables to their default initial values, including setting their color to black. 
clear_patches :: C Observer () IO ()
clear_patches = V.mapM_ (\ (MkPatch {pcolor_=pc, plabel_=pl, plabel_color_=plc, pvars_=po})  -> lift $ do
                            atomically $ writeTVar pc 0
                            atomically $ writeTVar pl ""
                            atomically $ writeTVar plc 9.9
                            atomically $ V.mapM_ (`writeTVar` 0) po -- patches-own to 0
                        ) __patches

{-# INLINE cp #-}
-- | alias for 'clear_patches'
cp :: C Observer () IO ()
cp = clear_patches


{-# INLINE clear_ticks #-}
-- | Clears the tick counter.
-- Does not set the counter to zero. After this command runs, the tick counter has no value. Attempting to access or update it is an error until reset-ticks is called. 
clear_ticks :: C Observer () IO ()
clear_ticks = lift $ writeIORef __tick (error "The tick counter has not been started yet. Use RESET-TICKS.")

{-# INLINE reset_ticks #-}
-- | Resets the tick counter to zero, sets up all plots, then updates all plots (so that the initial state of the world is plotted). 
reset_ticks :: C Observer () IO ()
reset_ticks = lift $ writeIORef __tick 0

{-# INLINE tick #-}
-- | Advances the tick counter by one and updates all plots. 
tick :: C Observer () IO ()
tick = tick_advance 1

{-# WARNING tick_advance "TODO: dynamic typing, float" #-}
{-# INLINE tick_advance #-}
-- | Advances the tick counter by number. The input may be an integer or a floating point number. (Some models divide ticks more finely than by ones.) The input may not be negative. 
tick_advance :: Double -> C Observer () IO ()
tick_advance n = lift $ modifyIORef' __tick (+n)

{-# INLINE butfirst #-}
-- | When used on a list, but-first reports all of the list items of list except the first
butfirst :: [a] -> [a]
butfirst = tail

{-# INLINE butlast #-}
-- | but-last reports all of the list items of list except the last. 
butlast :: [a] -> [a]
butlast = init

{-# INLINE emptyp #-}
-- | Reports true if the given list or string is empty, false otherwise. 
emptyp :: [a] -> Bool
emptyp = null

{-# INLINE first #-}
-- | On a list, reports the first (0th) item in the list. 
first :: [a] -> a
first = head

{-# INLINE foreach #-}
-- | With a single list, runs the task for each item of list. 
foreach :: STMorIO m => [a] -> (a -> C _s _s' m b) -> C _s _s' m ()
foreach = forM_

{-# INLINE fput #-}
-- | Adds item to the beginning of a list and reports the new list. 
fput :: a -> [a] -> [a]
fput = (:)

{-# WARNING histogram "TODO" #-}
-- | Histograms the values in the given list
-- Draws a histogram showing the frequency distribution of the values in the list. The heights of the bars in the histogram represent the numbers of values in each subrange. 
histogram :: t
histogram = todo

-- | Runs commands number times. 
repeat_ :: STMorIO m => Int -> C _s _s' m a -> C _s _s' m ()
repeat_ 0 _ = return ()
repeat_ n c = c >> repeat_ (n-1) c

{-# INLINE report #-}
-- | Immediately exits from the current to-report procedure and reports value as the result of that procedure. report and to-report are always used in conjunction with each other. 
-- | NB: IN HLogo, It does not exit the procedure, but it will if the report primitive happens to be the last statement called from the procedure
report :: STMorIO m => a -> C _s _s' m a
report = return


{-# INLINE item #-}
-- | On lists, reports the value of the item in the given list with the given index. 
item :: Int -> [a] -> a
item i l = l !! i

{-# INLINE list #-}
-- | Reports a list containing the given items.
list :: t -> t -> [t]
list x y = [x,y]

{-# INLINE lput #-}
-- | Adds value to the end of a list and reports the new list. 
lput :: a -> [a] -> [a]
lput x l = l ++ [x]

{-# INLINE memberp #-}
-- | For a list, reports true if the given value appears in the given list, otherwise reports false. 
memberp :: Eq a => a -> [a] -> Bool
memberp = elem


-- | Reports a list of length size containing values computed by repeatedly running the task. 
n_values :: (Eq a, STMorIO m, Num a) => a -> (a -> C _s _s' m t) -> C _s _s' m [t]
n_values 0 _ = return []
n_values s f = do
    h <- f s 
    t <- n_values (s-1) f
    return (h:t)

{-# WARNING position "TODO: requires dynamic typing" #-}
{-# INLINE position #-}
-- | On a list, reports the first position of item in list, or false if it does not appear. 
position :: (a -> Bool) -> [a] -> Maybe a
position = find

-- |  From an agentset, reports a random agent. If the agentset is empty, reports nobody.
-- From a list, reports a random list item. It is an error for the list to be empty. 
one_of :: F.Foldable t => t a -> C s _s' IO a
#if __GLASGOW_HASKELL__ < 710
one_of l = F.foldr (\_ _ ->  do
                      (_,_,tgen) <- Reader.ask
                      gen <- lift $ readIORef tgen
                      let (v,gen') = TF.randomR (0, F.foldl' (\c _ -> c+1) (-1) l) gen
                      lift $ writeIORef tgen $! gen'
                      return $ F.toList l !! v
                   ) (error "empty one_of") l
#else
one_of l | Prelude.null l = error "empty one_of"
         | otherwise = do
  (_,_,tgen) <- Reader.ask
  gen <- lift $ readIORef tgen
  let (v,gen') = randomR (0, Prelude.length l -1) gen
  lift $ writeIORef tgen $! gen'
  return $ F.toList l !! v
#endif


{-# RULES "one_of/Patches" one_of = one_of_patches #-}
one_of_patches :: Patches -> C s _s' IO Patch
one_of_patches l | V.null l = error "empty one_of"
                 | otherwise = do
  (_,_,tgen) <- Reader.ask
  gen <- lift $ readIORef tgen
  let (v,gen') = randomR (0, V.length l -1) gen
  lift $ writeIORef tgen $! gen'
  return $ l `V.unsafeIndex` v

{-# RULES "one_of/Links" one_of = one_of_links #-}
one_of_links :: Links -> C s _s' IO Link
one_of_links l | M.null l = error "empty one_of"
               | otherwise = do
  (_,_,tgen) <- Reader.ask
  gen <- lift $ readIORef tgen
  let (v,gen') = randomR (0, M.size l -1) gen
  lift $ writeIORef tgen $! gen'
  return $ snd $ M.elemAt v l

-- NOTE: one_of_turtles is probably not possible, because there is no indexing of an IntMap datastructure (elemAt)

-- |  From an agentset, reports an agentset of size size randomly chosen from the input set, with no repeats.
-- From a list, reports a list of size size randomly chosen from the input set, with no repeats. 
-- n_of :: Eq a => Int -> [a] -> C s _s' IO [a]
-- n_of n ls | n == 0     = return []
--           | n < 0     = error "negative index"
--           | otherwise = do
--   o <- one_of ls
--   ns <- n_of (n-1) (delete o ls)
--   return (o:ns)

-- adapted from the NetLogo code
-- TODO: generalization for lists, links. Turtles is difficult because IntMap does not provide indexing
n_of :: Int -> Patches -> C s _s' IO Patches
n_of n ps = let l = V.length ps
                go i j acc gen | n==j = (acc,gen)
                               | otherwise = 
                                  let (v,gen') = randomR (0,l-i) gen
                                  in if v < n - j
                                     then go (i+1) (j+1) (ps `V.unsafeIndex` (i-1):acc) gen'
                                     else go (i+1) j acc gen' 
            in do
              (_,_,tgen) <- Reader.ask
              gen <- lift $ readIORef tgen
              let (ps',gen') = go 1 0 [] gen 
              lift $ writeIORef tgen $! gen'
              return $ V.fromList ps'

-- n_of :: Indexable f => Int -> f a -> C s _s' IO (f a)
-- n_of 0 _ = mempty
-- n_of n f = liftM2 mappend (one_of f
--   ` n_of (n-1) f
-- class Foldable f => Indexable f where
--   index :: f a -> Int -> a
--   index f x = F.toList f !! x -- default (for turtles)
-- instance Indexable [] where -- lists
--   index = (!!)
-- instance Indexable V.Vector where -- patches
--   index = V.unsafeIndex
-- instance Indexable (M.Map k) where -- links
--   index f x = snd $ M.elemAt x f 


-- -- Uses instead agent_one_of when types match
-- -- {-# RULES "n_of/AgentRef" n_of = agent_n_of #-}
-- agent_n_of :: (Agent a) => Int -> [a] -> C s _s' STM [a]
-- agent_n_of n ls | n == 0     = return []
--                 | n < 0     = error "negative index"
--                 | otherwise = do
--   o <- agent_one_of ls
--   -- when (o == Nobody) $ error "empty agentset"
--   ns <- n_of (n-1) (delete o ls)
--   return (o:ns)


{-# WARNING min_one_of "TODO: currently deterministic and no randomness on tie breaking" #-}
-- | Reports a random agent in the agentset that reports the lowest value for the given reporter. If there is a tie, this command reports one random agent that meets the condition.
--min_one_of :: (Agent b, Foldable t, Ord (Many b b1)) => t b -> C (One b) p IO b1 -> C p p' IO b
min_one_of as r = snd <$> F.foldlM (\ acc@(mv1,_) a2 -> do
                                    v2 <- r `of_` a2
                                    return $ case mv1 of
                                             Nothing -> (Just v2,a2)
                                             Just v1 -> if v2 < v1
                                                       then (Just v2,a2)
                                                       else acc) (Nothing, error "nobody") as
  

{-# WARNING max_one_of "TODO: currently deterministic and no randomness on tie breaking. Can be improved by using minBound instead of Maybe" #-}
-- | Reports the agent in the agentset that has the highest value for the given reporter. If there is a tie this command reports one random agent with the highest value. If you want all such agents, use with-max instead. 
--max_one_of :: (Agent b, Foldable t, Ord (Many b b1)) => t b -> C (One b) p IO b1 -> C p p' IO b
max_one_of as r = snd <$> F.foldlM (\ acc@(mv1,_) a2 -> do
                                    v2 <- r `of_` a2
                                    return $ case mv1 of
                                             Nothing -> (Just v2,a2)
                                             Just v1 -> if v2 > v1
                                                       then (Just v2,a2)
                                                       else acc) (Nothing, error "nobody") as



{-# INLINE reduce #-}
-- | Reduces a list from left to right using the given task, resulting in a single value. (foldl)
reduce :: (b -> a -> b) -> b -> [a] -> b
reduce = foldl

{-# WARNING remove "TODO" #-}
-- | For a list, reports a copy of list with all instances of item removed. 
remove :: t
remove = todo

{-# INLINE remove_duplicates #-}
-- | Reports a copy of list with all duplicate items removed. The first of each item remains in place. 
remove_duplicates :: (STMorIO m, Eq a) => [a] -> C _s _s' m [a]
remove_duplicates = return . nub

{-# WARNING remove_item "TODO" #-}
-- | For a list, reports a copy of list with the item at the given index removed. 
remove_item :: t
remove_item = todo

{-# WARNING replace_item "TODO" #-}
-- | On a list, replaces an item in that list. index is the index of the item to be replaced, starting with 0. 
replace_item :: t
replace_item = todo

{-# WARNING sentence "TODO: requires dynamic_typing" #-}
{-# INLINE sentence #-}
-- | Makes a list out of the values. 
sentence :: [a] -> [a] -> [a]
sentence = (++)

{-# WARNING shuffle "TODO: make it tail-recursive, optimize with arrays <http://www.haskell.org/haskellwiki/Random_shuffle>" #-}
-- | Reports a new list containing the same items as the input list, but in randomized order. 
shuffle :: Eq a => [a] -> C s _s' IO [a]
shuffle [] = return []
shuffle [x] = return [x]
shuffle l = do 
  x <- one_of l
  liftM (x:) $ shuffle (delete x l)

{-# INLINE sort_ #-}
-- | Reports a sorted list of numbers, strings, or agents. 
sort_ :: (STMorIO m, Ord a) => [a] -> C _s _s' m [a]
sort_ = return . sort

{-# WARNING sort_by "TODO: requires dynamic_typing" #-}
{-# INLINE sort_by #-}
-- | If the input is a list, reports a new list containing the same items as the input list, in a sorted order defined by the boolean reporter task. 
sort_by :: STMorIO m => (a -> a -> Ordering) -> [a] -> C _s _s' m [a]
sort_by c l = return $ sortBy c l

-- | Reports a list of agents, sorted according to each agent's value for reporter. Ties are broken randomly. 
-- sort_on :: Ord a => CSTM a -> [AgentRef] -> CSTM [AgentRef]
sort_on = todo
-- sort_on rep as = do
--   (s,_,_) <- RWS.ask
--   xs <- lift . sequence $ [Reader.runReaderT rep (a,s) | a <- as]
--   let rs = zip xs as
--   return $ map snd $ sortBy (compare `on` fst) rs where


-- | Reports just a section of the given list or string, ranging between the first position (inclusive) and the second position (exclusive). 
-- 0-indexed
sublist :: [a] -> Int -> Int -> [a]
sublist l x y = take (y-x) . drop x $ l
{-# INLINE substring #-}
-- | Reports just a section of the given list or string, ranging between the first position (inclusive) and the second position (exclusive). 
substring :: [a] -> Int -> Int -> [a]
substring = sublist

{-# INLINE read_from_string #-}
-- | Interprets the given string as if it had been typed in the Command Center, and reports the resulting value.
read_from_string :: Read a => String -> a
read_from_string = read

{-# INLINE word #-}
-- | Concatenates the inputs together and reports the result as a string.
word :: Show a => [a] -> String
word = concatMap Prelude.show

{-# INLINE abs_ #-}
-- | Reports the absolute value of number. 
abs_ :: (STMorIO m, Num a) => a -> C _s _s' m a
abs_ = return . abs

{-# INLINE e #-}
-- | Mathematical Constant
e :: Double
e = exp 1

-- | Reports the cosine of the given angle. Assumes the angle is given in degrees. 
cos_ :: Double -> Double
cos_ = cos . toRadians

-- | Reports the sine of the given angle. Assumes the angle is given in degrees. 
sin_ :: Double -> Double
sin_ = sin . toRadians

-- | Reports the tangent of the given angle. 
tan_ :: Double -> Double
tan_ = tan . toRadians

-- | Internal
toRadians :: Floating a => a -> a
toRadians deg = deg * pi / 180

-- | Internal
toDegrees :: Floating a => a -> a
toDegrees rad = rad * 180 / pi

-- | Reports number1 modulo number2
mod_ :: Double -> Int -> Double
x `mod_` y | x == 0 = 0
           | otherwise =  fromIntegral (x' `mod` y) + (x - fromIntegral x')
           where x' = floor x

-- | Reports the arc cosine (inverse cosine) of the given number. 
acos_ :: Double -> Double
acos_ = toDegrees . acos

-- | Reports the arc sine (inverse sine) of the given number. 
asin_ :: Double -> Double
asin_ = toDegrees . asin

-- | Reports the arc tangent (inverse tangent) of the given number. 
atan_ :: RealFloat r => r -> r -> r
atan_ x y = toDegrees $ atan2 (toRadians x) (toRadians y)

{-# INLINE int #-}
-- | Reports the integer part of number -- any fractional part is discarded. 
int :: (Integral b, RealFrac a) => a -> b
int = truncate

{-# INLINE ln #-}
-- | Reports the natural logarithm of number, that is, the logarithm to the base e (2.71828...). 
ln :: Floating a => a -> a
ln = log

{-# INLINE log_ #-}
-- | Reports the logarithm of number in base base. 
log_ :: Double -> Double -> Double
log_ = flip logBase


{-# INLINE max_ #-}
-- | Reports the maximum number value in the list. It ignores other types of items. 
max_ :: Ord a => [a] -> a
max_ = maximum

{-# INLINE min_ #-}
-- Reports the minimum number value in the list. It ignores other types of items. 
min_ :: Ord a => [a] -> a
min_ = minimum

-- | Reports the statistical mean of the numeric items in the given list.
mean :: [Double] -> Double
mean l = let (t,n) = foldl' (\(b,c) a -> (a+b,c+1)) (0,0) l 
         in t / n

-- | Reports the statistical median of the numeric items of the given list.
median :: [Double] -> Double
median l = let (d, m) = Prelude.length l `divMod` 2
           in case m of
                1 -> l !! d
                0 -> (l !! d + l !! (d-1)) / 2
                _ -> throw DevException

{-# WARNING modes "TODO" #-}
-- | Reports a list of the most common item or items in list. 
modes :: t
modes = todo

{-# INLINE remainder #-}
-- | Reports the remainder when number1 is divided by number2. 
remainder :: Int -> Int -> Int
remainder = rem

{-# WARNING variance "TODO" #-}
-- | Reports the sample variance of a list of numbers. Ignores other types of items. 
variance :: t
variance = todo


{-# WARNING standard_deviation "TODO" #-}
-- | Reports the sample standard deviation of a list of numbers. Ignores other types of items. 
standard_deviation :: t -> t1
standard_deviation _l = todo

{-# WARNING subtract_headings "TODO? maybe it is finished" #-}
-- | Computes the difference between the given headings, that is, the number of degrees in the smallest angle by which heading2 could be rotated to produce heading1. 
subtract_headings :: STMorIO m => Double -> Double -> C _s _s' m Double
subtract_headings h1 h2 = let 
    h1' = if h1 < 0 || h1 >= 360
          then (h1 `mod_` 360 + 360) `mod_` 360
          else h1
    h2' = if h2 < 0 || h2 >= 360
          then (h2 `mod_` 360 + 360) `mod_` 360
          else h2
    diff = h1' - h2'
                           in return $
                             if diff > -180 && diff <= 180
                             then diff
                             else if diff > 0
                                  then diff - 360
                                  else diff + 360

-- let r1 = h2 - h1 `mod_` 180
                          --     r2 = h1 - h2 `mod_` 180
                          -- in return $
                          --   if abs r1 < abs r2
                          --   then if h2 > 180 then -r1 else r1
                          --   else if h2 > 180 then -r2 else r2

-- | The link makes itself invisible. 
hide_link :: C Link _s' STM ()
hide_link = do
  (MkLink {lhiddenp_ = h},_,_) <- Reader.ask
  lift $ writeTVar h True

-- | The turtle becomes visible again. 
show_link :: C Link _s' STM ()
show_link = do
  (MkLink {lhiddenp_ = h},_,_) <- Reader.ask
  lift $ writeTVar h False


-- | Reports the distance between the endpoints of the link. 
link_length :: C Link _s' STM Double
link_length = do
    (MkLink {end1_ =f, end2_ = t},_,_) <- Reader.ask
    MkTurtle {xcor_ = fx, ycor_ = fy} <- turtle f
    MkTurtle {xcor_ = tx, ycor_ = ty} <- turtle t
    x <- lift $ readTVar fx
    y <- lift $ readTVar fy
    x' <- lift $ readTVar tx
    y' <- lift $ readTVar ty
    return $ sqrt (delta x x' (max_pxcor_ cmdOpt) ^ (2 :: Int) + 
                delta y y' (max_pycor_ cmdOpt) ^ (2 :: Int))



-- | Report the undirected link between turtle and the caller. If no link exists then it reports nobody. 
-- link_with :: [Turtle] -> C Turtle _s' STM [Link]
-- link_with [MkTurtle {who_=x}] = do
--    (MkTurtle {who_=y},_) <- RWS.ask
--    lxy <- link x y
--    lyx <- link y x
--    return $ case (lxy,lyx) of
--               ([Nobody], [Nobody]) -> [Nobody]
--               ([Nobody], _) -> error "directed link"
--               ([LinkRef _ _], [LinkRef _ _]) -> lxy -- return arbitrary 1 of the two link positions
--               (_, [Nobody]) -> error "directed link"
--               _ -> throw DevException
-- link_with a = throw $ TypeException "single turtle"

  
-- | Report the directed link from turtle to the caller. If no link exists then it reports nobody. 
-- in_link_from :: [Turtle] -> C Turtle _s' STM [Link]
-- in_link_from [MkTurtle {who_=x}] = do
--    (MkTurtle {who_=y},_) <- RWS.ask
--    lxy <- link x y
--    lyx <- link y x
--    return $ case (lxy,lyx) of
--               ([Nobody], _) -> [Nobody]
--               (_, [Nobody]) -> lxy
--               ([LinkRef _ _], [LinkRef _ _]) -> error "undirected link"
--               _ -> throw DevException
-- in_link_from a = throw $ TypeException "turtle"



-- | Reports the directed link from the caller to turtle. If no link exists then it reports nobody. 
-- out_link_to :: [Turtle] -> C Turtle _s' STM [Link]
-- out_link_to [MkTurtle {who_=x}] = do
--    (MkTurtle {who_=y},_) <- RWS.ask
--    lxy <- link x y
--    lyx <- link y x
--    return $ case (lyx,lxy) of
--               ([Nobody], _) -> [Nobody]
--               (_, [Nobody]) -> lyx
--               ([LinkRef _ _], [LinkRef _ _]) -> error "undirected link"
--               _ -> throw DevException
-- out_link_to a = throw $ TypeException "turtle" (head a)


{-# WARNING my_links "TODO" #-}
-- | Reports an agentset of all undirected links connected to the caller. 
my_links :: C Turtle _s' STM [Link]
my_links = do
  (MkTurtle {who_=_x},_,_) <- Reader.ask 
  _ls <- lift $ readTVar __links
  todo
  -- return $ map (uncurry LinkRef) $ M.assocs $ M.intersection (M.filterWithKey (\ (f,_) _ -> f == x) ls) (M.filterWithKey (\ (_,t) _ -> t == x) ls)

{-# WARNING my_out_links "TODO" #-}
-- | Reports an agentset of all the directed links going out from the caller to other nodes. 
my_out_links :: C Turtle _s' STM [Link]
my_out_links = do
  (MkTurtle {who_=_x},_,_) <- Reader.ask 
  _ls <- lift $ readTVar __links
  todo 
  -- return $ map (uncurry LinkRef) $ M.assocs $ M.filterWithKey (\ (f,_) _ -> f == x) ls

{-# WARNING my_in_links "TODO" #-}
-- |  Reports an agentset of all the directed links coming in from other nodes to the caller. 
my_in_links :: C Turtle _s' STM [Link]
my_in_links = do
  (MkTurtle {who_=_x},_,_) <- Reader.ask 
  _ls <- lift $ readTVar __links
  todo
  -- return $ map (uncurry LinkRef) $ M.assocs $ M.filterWithKey (\ (_,t) _ -> t == x) ls

-- | Ties end1 and end2 of the link together. If the link is a directed link end1 is the root turtle and end2 is the leaf turtle. The movement of the root turtle affects the location and heading of the leaf turtle. If the link is undirected the tie is reciprocal so both turtles can be considered root turtles and leaf turtles. Movement or change in heading of either turtle affects the location and heading of the other turtle. 
tie :: C Link _s' STM ()
tie = do
  (MkLink {tie_mode = t},_,_) <- Reader.ask
  lift $ writeTVar t Fixed

-- | Unties end2 from end1 (sets tie-mode to "none") if they were previously tied together. If the link is an undirected link, then it will untie end1 from end2 as well. It does not remove the link between the two turtles. 
untie :: C Link _s' STM ()
untie = do
  (MkLink {tie_mode = t},_,_) <- Reader.ask
  lift $ writeTVar t None

end1 :: C Link _s' STM Turtle
end1 = do
  (MkLink {end1_ = e1},_,_) <- Reader.ask
  turtle e1

end2 :: C Link _s' STM Turtle
end2 = do
  (MkLink {end2_ = e2},_,_) <- Reader.ask
  turtle e2


{-# INLINE atomic #-}
-- | lifting STM to IO, a wrapper to 'atomically' that optionally (based on a CPP flag) can capture STM statistics 
atomic :: C _s _s' STM a -> C _s _s' IO a
atomic comms = 
#ifndef STATS_STM
       Reader.mapReaderT atomically comms
#else
    do
      lift $ incrCounter_ 1 counterSTMCommits --  it should be run afterwards, but we can assume the transaction will be succesful eventually
      Reader.mapReaderT (\ stm -> atomically (unsafeIOToSTM (incrCounter_ 1 counterSTMLoops) >> stm)) comms 
#endif


-- | Internal
--
-- plus one because we need a new generator for the parent ask/ofcaller too
numBits :: Int
numBits = ceiling ((logBase 2 $ fromIntegral $ numCapabilities + 1) :: Double)

-- same implementations
instance Agent Turtle where
    ask f a = Reader.withReaderT (\ (s,_,rng) -> (a,s,rng)) f >> return ()
    ask_async f a = Reader.withReaderT (\ (s,_,rng) -> (a,s,rng)) f >> return () -- same as ask. actually ask_async on single-agent is a misnomer because it is not asynchronous
    of_ f a = Reader.withReaderT (\ (s,_,rng) -> (a,s,rng)) f
instance Agent Patch where
    ask f a = Reader.withReaderT (\ (s,_,rng) -> (a,s,rng)) f >> return ()
    ask_async f a = Reader.withReaderT (\ (s,_,rng) -> (a,s,rng)) f >> return () -- same as ask. actually ask_async on single-agent is a misnomer because it is not asynchronous
    of_ f a = Reader.withReaderT (\ (s,_,rng) -> (a,s,rng)) f
instance Agent Link where
    ask f a = Reader.withReaderT (\ (s,_,rng) -> (a,s,rng)) f >> return ()
    ask_async f a = Reader.withReaderT (\ (s,_,rng) -> (a,s,rng)) f >> return () -- same as ask. actually ask_async on single-agent is a misnomer because it is not asynchronous
    of_ f a = Reader.withReaderT (\ (s,_,rng) -> (a,s,rng)) f


instance Agent Turtles where
    ask f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        __tg <- ThreadG.new
        mapM_ (\ (tslice,core,g') -> do
                 tgen' <- newIORef g'
                 ThreadG.forkOn core __tg $ F.mapM_ (\ t -> Reader.runReaderT f (t,s,tgen')) tslice
             ) (zip3 (splitTurtles numCapabilities [as]) [1..numCapabilities] gs)
        ThreadG.wait __tg

    ask_async f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        mapM_ (\ (tslice,core,g') -> do
                 tgen' <- newIORef g'
                 Thread.forkOn core $ F.mapM_ (\ t -> Reader.runReaderT f (t,s,tgen')) tslice
             ) (zip3 (splitTurtles numCapabilities [as]) [1..numCapabilities] gs)
        -- does not wait

    of_ f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        ws <- mapM (\ (tslice,core,g') -> do
                     tgen' <- newIORef g'
                     snd <$> Thread.forkOn core (IM.elems <$> T.mapM (\ t -> Reader.runReaderT f (t,s,tgen')) tslice)
                  ) (zip3 (splitTurtles numCapabilities [as]) [1..numCapabilities] gs)
        concat <$> sequence [Thread.result =<< w | w <- ws]

instance With Turtles where
    with f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        ws <- mapM (\ (tslice,core,g') -> do
                     tgen' <- newIORef g'
                     snd <$> Thread.forkOn core (filterM (\ (_,t) -> Reader.runReaderT f (t,s,tgen')) $ IM.toAscList tslice)
                  ) (zip3 (splitTurtles numCapabilities [as]) [1..numCapabilities] gs)
        IM.fromDistinctAscList . concat <$> sequence [Thread.result =<< w | w <- ws]

splitTurtles :: Int -> [IM.IntMap Turtle] -> [IM.IntMap Turtle]
splitTurtles 1 acc = acc
splitTurtles n acc = splitTurtles (n `quot` 2) $ concatMap IM.splitRoot acc 

splitPatches :: Int -> Int -> [(Int,Int,Int)]
splitPatches width n = let (q,r) = width `quotRem` n
                           splitPatches' (0,s,l) c = (0, q+s, (s,q,c):l)
                           splitPatches' (r',s,l) c = (r'-1, q+s+1, (s,q+1,c):l)
                       in  case (foldl' splitPatches' (r,0,[]) ([1..n] :: [Int])) of
                             (_,_,res) -> res

-- | prop> length (splitCapabilities n g) == n + 1
splitCapabilities :: SM.SMGen -> [SM.SMGen]
splitCapabilities = splitCapabilities' (numCapabilities+1) -- + 1 for the observer's generator
  where
    splitCapabilities' n  g | n < 1 = [g]
                            | n < 3 = let (g1, g2) = SM.splitSMGen g in [g1,g2]
                            | otherwise = let (g1,g2) = SM.splitSMGen g
                                          in splitCapabilities' (n-4) g1 ++ splitCapabilities' (n-2) g2
instance Agent Patches where
    ask f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
              g <- readIORef tgen
              let (g0:gs) = splitCapabilities g
              writeIORef tgen $! g0
              __tg <- ThreadG.new
              mapM_ (\ ((start,size,core),g') -> do
                      tgen' <- newIORef g'
                      ThreadG.forkOn core __tg $ V.mapM_ (\ p -> Reader.runReaderT f (p,s,tgen')) (V.unsafeSlice start size as)
                   ) (zip (splitPatches (V.length as) numCapabilities) gs)
              ThreadG.wait __tg                               

    ask_async f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
              g <- readIORef tgen
              let (g0:gs) = splitCapabilities g
              writeIORef tgen $! g0
              mapM_ (\ ((start,size,core),g') -> do
                      tgen' <- newIORef g'
                      Thread.forkOn core $ V.mapM_ (\ p -> Reader.runReaderT f (p,s,tgen')) (V.unsafeSlice start size as)
                   ) (zip (splitPatches (V.length as) numCapabilities) gs)
              -- does not wait

    of_ f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        ws <- mapM (\ ((start,size,core),g') -> do
                     tgen' <- newIORef g'
                     snd <$> Thread.forkOn core (V.toList <$> V.mapM (\ p -> Reader.runReaderT f (p,s,tgen')) (V.unsafeSlice start size as))
                  ) (zip (splitPatches (V.length as) numCapabilities) gs)
        concat <$> sequence [Thread.result =<< w | w <- ws]

instance With Patches where
    with f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        ws <- mapM (\ ((start,size,core),g') -> do
                     tgen' <- newIORef g'
                     snd <$> Thread.forkOn core (V.filterM (\ p -> Reader.runReaderT f (p,s,tgen')) (V.unsafeSlice start size as))
                  ) (zip (splitPatches (V.length as) numCapabilities) gs)
        V.concat <$> sequence [Thread.result =<< w | w <- ws]

instance Agent Links where
    ask f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do 
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        __tg <- ThreadG.new
        mapM_ (\ ((core, asSection),g') -> do
                   tgen' <- newIORef g'
                   ThreadG.forkOn core __tg $ mapM_ (\ a -> Reader.runReaderT f (a,s,tgen')) asSection
              ) (zip (splitLinks numCapabilities $ M.elems as) gs)
        ThreadG.wait __tg

    ask_async f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do 
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        mapM_ (\ ((core, asSection),g') -> do
                   tgen' <- newIORef g'
                   Thread.forkOn core $ mapM_ (\ a -> Reader.runReaderT f (a,s,tgen')) asSection
              ) (zip (splitLinks numCapabilities $ M.elems as) gs)
        -- does not wait

    of_ f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        ws <- mapM (\ ((core, asi),g') -> do
                     tgen' <- newIORef g'
                     snd <$> Thread.forkOn core (mapM (\ a -> Reader.runReaderT f (a,s,tgen')) asi)
                  ) (zip (splitLinks numCapabilities $ M.elems as) gs)
        concat <$> sequence [Thread.result =<< w | w <- ws]


instance With Links where
    with f as = do
      (s,_,tgen) <- Reader.ask
      lift $ do
        g <- readIORef tgen
        let (g0:gs) = splitCapabilities g
        writeIORef tgen $! g0
        ws <- mapM (\ ((core, asi),g') -> do
                     tgen' <- newIORef g'
                     snd <$> Thread.forkOn core (filterM (\ (_,a) -> Reader.runReaderT f (a,s,tgen')) asi)
                  ) (zip (splitLinks numCapabilities $ M.toAscList as) gs)
        M.fromDistinctAscList . concat <$> sequence [Thread.result =<< w | w <- ws]

-- | internal
splitLinks :: Int -> [a] -> [(Int, [a])]
splitLinks 1 l = [(1,l)]
splitLinks n l = let (d,m) = Prelude.length l `quotRem` n
                     split' 0 _ _ = []
                     split' x 0 l' = let (t, rem_list) = splitAt d l'
                                     in (x,t) : split' (x-1) 0 rem_list
                     split' x m' l' = let (t, rem_list) = splitAt (d+1) l'
                                      in (x,t) : split' (x-1) (m'-1) rem_list
                 in split' n m l

-- | For an agent, reports the value of the reporter for that agent (turtle or patch). 
--  For an agentset, reports a list that contains the value of the reporter for each agent in the agentset (in random order). 
                 
{-# WARNING loop  "TODO: use MaybeT or ErrorT" #-}
-- |  Runs the list of commands forever, or until the current procedure exits through use of the stop command or the report command. 
-- NB: Report command will not stop it in HLogo, only the stop primitive. 
-- This command is only run in IO, bcs the command has been implemented
-- using exceptions and exceptions don't work the same in STM. Also
-- it avoids common over-logging that can happen in STM.
loop :: C _s _s' IO a -> C _s _s' IO ()
loop c = forever c `catchIO` \ StopException -> return ()

{-# INLINE stop #-}
-- | This agent exits immediately from the enclosing to-procedure that was called from 'ask', or ask-like construct (e.g. crt, hatch, sprout). Only the current procedure stops, not all execution for the agent. Also can exit from a top-level (observer) procedure.
stop :: a
stop = throw StopException

{-# WARNING while  "TODO: use MaybeT or ErrorT" #-}
-- | If reporter reports false, exit the loop. Otherwise run commands and repeat. 
-- This command is only run in IO, bcs the command has been implemented
-- using exceptions and exceptions don't work the same in STM. Also
-- it avoids common over-logging that can happen in STM.
while :: C _s _s' IO Bool -> C _s _s' IO a -> C _s _s' IO ()
while r c = r >>= \ res -> when res $ (c >> while r c) `catchIO` (\ StopException -> return ())

is_directed_linkp :: STMorIO m => Link -> C _s _s' m Bool
is_directed_linkp (MkLink {directed_ = d}) = return d

is_undirected_linkp :: STMorIO m => Link -> C _s _s' m Bool
is_undirected_linkp (MkLink {directed_ = d}) = return $ not d

-- | This turtle creates number new turtles. Each new turtle inherits of all its variables, including its location, from its parent. (Exceptions: each new turtle will have a new who number)
hatch :: Int -> C Turtle _s' STM [Turtle]
hatch n = do
    (MkTurtle _w bd c h x y s l lc hp sz ps pm tarr, _,_) <- Reader.ask
    -- todo: this whole code could be made faster by readTVar of the attributes only once and then newTVar multiple times from the 1 read
    let newArray = V.mapM (newTVar <=< readTVar) tarr
    let newTurtles w = return . IM.fromDistinctAscList =<< sequence [do
                                                                        t <- MkTurtle i <$>
                                                                            (newTVar =<< readTVar bd) <*>
                                                                            (newTVar =<< readTVar c) <*>
                                                                            (newTVar =<< readTVar h) <*>
                                                                            (newTVar =<< readTVar x) <*>
                                                                            (newTVar =<< readTVar y) <*>
                                                                            (newTVar =<< readTVar s) <*> 
                                                                            (newTVar =<< readTVar l) <*>
                                                                            (newTVar =<< readTVar lc) <*>
                                                                            (newTVar =<< readTVar hp) <*>
                                                                            (newTVar =<< readTVar sz) <*>
                                                                            (newTVar =<< readTVar ps) <*>
                                                                            (newTVar =<< readTVar pm) <*>
                                                                            newArray
                                                                        return (i, t) | i <- [w..w+n-1]]
    oldWho <- lift $ readTVar __who
    lift $ modifyTVar' __who (n +)
    ns <- lift $ newTurtles oldWho
    lift $ modifyTVar' __turtles (`IM.union` ns) 
    return $ IM.elems ns -- todo: can be optimized

{-# INLINE turtles_on #-}
-- | Reports an agentset containing all the turtles that are on the given patch or patches, or standing on the same patch as the given turtle or turtles. 
turtles_on as = IM.unions <$> turtles_here `of_` as
    
{-# WARNING at_points "TODO: also has to support the Observer as Caller. A TurtleObserver typeclass" #-}
-- |  Reports a subset of the given agentset that includes only the agents on the patches the given distances away from this agent. The distances are specified as a list of two-item lists, where the two items are the x and y offsets.
-- If the caller is the observer, then the points are measured relative to the origin, in other words, the points are taken as absolute patch coordinates.
-- If the caller is a turtle, the points are measured relative to the turtle's exact location, and not from the center of the patch under the turtle. 
at_points :: (TurtlePatch a) => [a] -> [(Double, Double)] -> C Turtle _s' STM [a]
at_points [] _ = return []
at_points (_a:_as) _ds = todo
  -- do
  -- (_,_,s,_,_) <- RWS.ask
  -- (x,y) <- case s of
  --           ObserverRef _ -> return (0,0)
  --           PatchRef (px, py) _ -> return (fromIntegral px, fromIntegral py)
  --           TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty}) -> lift $ liftM2 (,) (readTVar tx) (readTVar ty)
  --           LinkRef _ _ -> throw $ TypeException "observer/patch/turtle" s
  --           Nobody -> throw DevException

-- | Runs the given commands only if it's been more than number seconds since the last time this agent ran them in this context. Otherwise, the commands are skipped. 
-- | NB: Works differently than NetLogo, in that only the calling thread is suspended, not the whole simulation
every :: Double -> C _s _s' IO a -> C _s _s' IO ()
every n a = a >> wait n

{-# INLINE wait #-}
-- | Wait the given number of seconds. (This needn't be an integer; you can specify fractions of seconds.) Note that you can't expect complete precision; the agent will never wait less than the given amount, but might wait slightly more. 
-- | NB: Works differently than NetLogo, in that only the calling thread is suspended, not the whole simulation
wait :: Double -> C _s _s' IO ()
wait n = lift $ threadDelay (truncate $ n * 1000000)

stats_stm :: C Observer () IO (String,String,String)
stats_stm = 
#ifndef STATS_STM 
   error "library not compiled with stats-stm flag enabled"
#else
   lift $ do
    r <- readCounter counterSTMLoops
    s <- readCounter counterSTMCommits
    let retryRatio = fromIntegral (r-s) / fromIntegral s
    return ("Number of retries: " ++ Prelude.show (r-s) 
         ,"\nNumber of commits: " ++ Prelude.show s
         ,"Retry ratio: " ++ Prelude.show retryRatio)
#endif


with_breed :: TurtleLink s => (String -> String) -> C s _s' STM ()
with_breed f = do
  (s,_,_) <- Reader.ask
  lift $ modifyTVar' (breed_ s) f

with_color :: TurtleLink s => (Double -> Double) -> C s _s' STM ()
with_color f = do
  (s,_,_) <- Reader.ask
  lift $ modifyTVar' (color_ s) f

with_heading :: (Double -> Double) -> C Turtle _s' STM ()
with_heading f = do
  (MkTurtle {heading_ = tb},_,_) <- Reader.ask
  lift $ modifyTVar' tb f

with_shape :: TurtleLink s => (String -> String) -> C s _s' STM ()
with_shape f = do
  (s,_,_) <- Reader.ask
  lift $ modifyTVar' (shape_ s) f

with_label :: TurtleLink s => (String -> String) -> C s _s' STM ()
with_label f = do
  (s,_,_) <- Reader.ask
  lift $ modifyTVar' (label_ s) f

with_label_color :: TurtleLink s => (Double -> Double) -> C s _s' STM ()
with_label_color f = do
  (s,_,_) <- Reader.ask
  lift $ modifyTVar' (label_color_ s) f

with_size :: (Double -> Double) -> C Turtle _s' STM ()
with_size f = do
  (MkTurtle {size_ = tb},_,_) <- Reader.ask
  lift $ modifyTVar' tb f

with_pcolor :: TurtlePatch s => (Double -> Double) -> C s _s' STM ()
with_pcolor f = do
  (s,_,_) <- Reader.ask
  (MkPatch {pcolor_ = tb}) <- patch_on_ s
  lift $ modifyTVar' tb f

with_plabel :: TurtlePatch s => (String -> String) -> C s _s' STM ()
with_plabel f = do
  (s,_,_) <- Reader.ask
  (MkPatch {plabel_ = tb}) <- patch_on_ s
  lift $ modifyTVar' tb f

with_plabel_color :: TurtlePatch s => (Double -> Double) -> C s _s' STM ()
with_plabel_color f = do
  (s,_,_) <- Reader.ask
  (MkPatch {plabel_color_ = tb}) <- patch_on_ s
  lift $ modifyTVar' tb f

snapshot :: C Observer () IO ()
snapshot = do
             ticksNow <- ticks
             ps <- patch_size
             max_x <- max_pxcor
             min_x <- min_pycor
             let sizeSpec = Diag.mkWidth (fromIntegral (ps * (max_x + abs min_x + 1)))
             let output = "snapshot" ++ Prelude.show (round ticksNow :: Int) ++ ".eps"
             prs <- patches
             diagPatches <- lift $ V.mapM (\ (MkPatch {pxcor_ = px, pycor_ = py, pcolor_ = pc, plabel_ = pl}) -> do 
                                   c <- readTVarIO pc
                                   --t <- readTVarIO pl
                                   let [r,g,b] = extract_rgb c
                                   return (Diag.p2 (fromIntegral px, fromIntegral py), Diag.square 1 Diag.# Diag.fc (sRGB24 r g b) Diag.# Diag.lw Diag.none :: Diag.Diagram Postscript)
                                ) prs 
             trs <- turtles
             diagTurtles <- lift $ T.mapM (\ (MkTurtle {xcor_ = tx, ycor_ = ty, tcolor_ = tc, heading_ = th, size_ = ts}) -> do 
                                          x <- readTVarIO tx
                                          y <- readTVarIO ty
                                          c <- readTVarIO tc
                                          h <- readTVarIO th
                                          s <- readTVarIO ts
                                          let [r,g,b] = extract_rgb c
                                          return (Diag.p2 (x, y), Diag.eqTriangle s Diag.# Diag.fc (sRGB24 r g b) Diag.# Diag.scaleX 0.5 Diag.# Diag.rotate (-h Diag.@@ Diag.deg) :: Diag.Diagram Postscript)
                                ) trs

             lift $ Diag.renderDia Postscript (PostscriptOptions output sizeSpec EPS) (Diag.position (IM.elems diagTurtles) `Diag.atop` Diag.position (V.toList diagPatches))
    

extract_rgb :: Double -> [Word8]
extract_rgb c | c == 0 = [0,0,0]
              | c == 9.9 = [255,255,255]
              | otherwise = let colorTimesTen = truncate(c * 10)
                                baseIndex = colorTimesTen `div` 100
                                colorsRGB = [
                                 140, 140, 140, -- gray (5)
                                 215, 48, 39, -- red (15)
                                 241, 105, 19, -- orange (25)
                                 156, 109, 70, -- brown (35)
                                 237, 237, 47, -- yellow (45)
                                 87, 176, 58, -- green (55)
                                 42, 209, 57, -- lime (65)
                                 27, 158, 119, -- turquoise (75)
                                 82, 196, 196, -- cyan (85)
                                 43, 140, 190, -- sky (95)
                                 50, 92, 168, -- blue (105)
                                 123, 78, 163, -- violet (115)
                                 166, 25, 105, -- magenta (125)
                                 224, 126, 149, -- pink (135)
                                 0, 0, 0, -- black
                                 255, 255, 255 -- white
                                          ]
                                r = colorsRGB !! (baseIndex * 3 + 0)
                                g = colorsRGB !! (baseIndex * 3 + 1)
                                b = colorsRGB !! (baseIndex * 3 + 2)
                                step = fromIntegral (colorTimesTen `rem` 100 - 50) / 50.48 + 0.012 :: Double
                            in
                              if step < 0
                              then [truncate(fromIntegral r * step) +r, truncate(fromIntegral g*step)+g, truncate(fromIntegral b*step)+b]
                              else [truncate((255 - fromIntegral r)*step)+r, truncate((255 - fromIntegral g)*step)+g, truncate((255 - fromIntegral b)*step)+b]

{-# WARNING approximate_rgb "TODO" #-}
approximate_rgb :: a
approximate_rgb = todo

-- | Reports an agentset containing the 8 surrounding patches
neighbors :: (STMorIO m, TurtlePatch s) => C s _s' m Patches
neighbors = do
    (s,_,_) <- Reader.ask
    MkPatch {pxcor_ = x, pycor_ = y} <- patch_on_ s
    return $ V.fromList $ catMaybes [patch' (fromIntegral x') (fromIntegral y')
                                    | (x',y') <- [ (x-1,y-1)
                                                 , (x-1,y)
                                                 , (x-1, y+1)
                                                 , (x, y-1)
                                                 , (x, y+1)
                                                 , (x+1, y-1)
                                                 , (x+1, y)
                                                 , (x+1, y+1)
                                                 ]
                                    ]
                      
-- | Reports an agentset containing the 4 surrounding patches
neighbors4 :: (STMorIO m, TurtlePatch s) => C s _s' m Patches
neighbors4 = do
    (s,_,_) <- Reader.ask
    (MkPatch {pxcor_ = x, pycor_ = y}) <- patch_on_ s
    return $ V.fromList $ catMaybes [patch' (fromIntegral x') (fromIntegral y')
                                    | (x',y') <- [ (x-1,y)
                                                 , (x+1, y)
                                                 , (x, y-1)
                                                 , (x, y+1)
                                                 ]
                                    ]

{-# SPECIALIZE  turtles_here :: TurtlePatch s => C s _s' STM Turtles #-}
{-# SPECIALIZE  turtles_here :: TurtlePatch s => C s _s' IO Turtles #-}
{-# WARNING turtles_here "TODO: use a custom filterM for IntMap, instead of (fromList . filterM. toList)" #-}
-- |  Reports an agentset containing all the turtles on the caller's patch (including the caller itself if it's a turtle). 
turtles_here :: (TurtlePatch s, STMorIO m) => C s _s' m Turtles
turtles_here = do
    (s,_,_) <- Reader.ask
    (MkPatch {pxcor_ = px, pycor_ = py}) <- patch_on_ s
    liftM IM.fromDistinctAscList $ filterM (\ (_, MkTurtle {xcor_ = x, ycor_ = y}) -> do 
                                  x' <- readTVarSI x
                                  y' <- readTVarSI y
                                  return $ round x' == px && round y' == py
                                            ) =<< (liftM IM.toAscList $ turtles)

{-# SPECIALIZE  turtles_at :: TurtlePatch s => Double -> Double -> C s _s' STM Turtles #-}
{-# SPECIALIZE  turtles_at :: TurtlePatch s => Double -> Double -> C s _s' IO Turtles #-}
{-# WARNING turtles_at "TODO: use a custom filterM for IntMap, instead of (fromList . filterM. toList)" #-}
-- |  Reports an agentset containing the turtles on the patch (dx, dy) from the caller. (The result may include the caller itself if the caller is a turtle.) 
turtles_at :: (TurtlePatch s, STMorIO m) => Double -> Double -> C s _s' m Turtles -- ^ dx -> dy -> CSTM (Set AgentRef)
turtles_at x y = do
    MkPatch {pxcor_=px, pycor_=py} <- patch_at x y
    liftM IM.fromDistinctAscList $ filterM (\ (_, MkTurtle {xcor_ = tx, ycor_ = ty}) -> do 
                                   x' <- readTVarSI tx
                                   y' <- readTVarSI ty
                                   return $ round x' == px && round y' == py
                                           ) =<< (liftM IM.toAscList $ turtles)

{-# SPECIALIZE INLINE patch_here :: C Turtle _s' STM Patch #-}
{-# SPECIALIZE INLINE patch_here :: C Turtle _s' IO Patch #-}
-- | patch-here reports the patch under the turtle. 
patch_here :: STMorIO m => C Turtle _s' m Patch
patch_here = do
    (MkTurtle {xcor_ = tx, ycor_ = ty},_,_) <- Reader.ask
    x <- readTVarSI tx
    y <- readTVarSI ty
    let mix = min_pxcor_ cmdOpt
        miy = min_pycor_ cmdOpt
        max = max_pxcor_ cmdOpt
        may = max_pycor_ cmdOpt
        norm_x = if horizontal_wrap_ cmdOpt then ((round x + max) `mod` (max-mix+1)) + mix else round x
        norm_y = if vertical_wrap_ cmdOpt then ((round y + may) `mod` (may-miy+1)) + miy else round y
    return $ __patches `V.unsafeIndex` (((norm_x-mix)*(may-miy+1))+(norm_y-miy))

{-# SPECIALIZE INLINE turtles :: C _s _s' STM Turtles #-}
{-# SPECIALIZE INLINE turtles :: C _s _s' IO Turtles #-}
-- | Reports the agentset consisting of all turtles. 
turtles :: STMorIO m => C _s _s' m Turtles
turtles = readTVarSI __turtles

{-# SPECIALIZE INLINE turtle :: Int -> C _s _s' STM Turtle #-}
{-# SPECIALIZE INLINE turtle :: Int -> C _s _s' IO Turtle #-}
-- | Reports the turtle with the given who number, or nobody if there is no such turtle. For breeded turtles you may also use the single breed form to refer to them. 
turtle :: STMorIO m => Int -> C _s _s' m Turtle
turtle n = do
    ts <- readTVarSI __turtles
    maybe nobody return $ IM.lookup n ts


{-# SPECIALIZE INLINE heading :: C Turtle _s' STM Double #-}
{-# SPECIALIZE INLINE heading :: C Turtle _s' IO Double #-}
-- | This is a built-in turtle variable. It indicates the direction the turtle is facing. 
heading :: STMorIO m => C Turtle _s' m Double
heading = do
    (MkTurtle {heading_ = h},_,_) <- Reader.ask
    readTVarSI h


{-# SPECIALIZE INLINE xcor :: C Turtle _s' STM Double #-}
{-# SPECIALIZE INLINE xcor :: C Turtle _s' IO Double #-}
-- | This is a built-in turtle variable. It holds the current x coordinate of the turtle. 
xcor :: STMorIO m => C Turtle _s' m Double
xcor = do
    (MkTurtle {xcor_ = x},_,_) <- Reader.ask
    readTVarSI x

{-# SPECIALIZE INLINE ycor :: C Turtle _s' STM Double #-}
{-# SPECIALIZE INLINE ycor :: C Turtle _s' IO Double #-}
-- | This is a built-in turtle variable. It holds the current y coordinate of the turtle.
ycor :: STMorIO m => C Turtle _s' m Double
ycor = do
    (MkTurtle {ycor_ = y},_,_) <- Reader.ask
    readTVarSI y

{-# SPECIALIZE INLINE pcolor :: C Turtle _s' STM Double #-}
{-# SPECIALIZE INLINE pcolor :: C Turtle _s' IO Double #-}
{-# SPECIALIZE INLINE pcolor :: C Patch _s' STM Double #-}
{-# SPECIALIZE INLINE pcolor :: C Patch _s' IO Double #-}
pcolor :: STMorIO m => TurtlePatch s => C s _s' m Double
pcolor = do
    (s,_,_) <- Reader.ask
    readTVarSI =<< (liftM pcolor_ $ patch_on_ s)

{-# SPECIALIZE INLINE plabel :: C Turtle _s' STM String #-}
{-# SPECIALIZE INLINE plabel :: C Turtle _s' IO String #-}
{-# SPECIALIZE INLINE plabel :: C Patch _s' STM String #-}
{-# SPECIALIZE INLINE plabel :: C Patch _s' IO String #-}
plabel :: STMorIO m => TurtlePatch s => C s _s' m String
plabel = do
    (s,_,_) <- Reader.ask
    readTVarSI =<< (liftM plabel_ $ patch_on_ s)


{-# SPECIALIZE INLINE color :: TurtleLink s => C s _s' STM Double #-}
{-# SPECIALIZE INLINE color :: TurtleLink s => C s _s' IO Double #-}
-- | This is a built-in turtle variable. It holds the turtle's "who number" or ID number, an integer greater than or equal to zero. You cannot set this variable; a turtle's who number never changes. 
color :: STMorIO m => TurtleLink s => C s _s' m Double
color = do
    (s,_,_) <- Reader.ask
    readTVarSI (color_ s)


{-# SPECIALIZE INLINE breed :: TurtleLink s => C s _s' STM String #-}
{-# SPECIALIZE INLINE breed :: TurtleLink s => C s _s' IO String #-}
breed :: STMorIO m => TurtleLink s => C s _s' m String
breed = do
    (s,_,_) <- Reader.ask
    readTVarSI (breed_ s)


-- -- | Reports the distance from this agent to the given turtle or patch. 
-- distance :: (TurtlePatch a, TurtlePatch s) => [a] -> C s _s' m Double

-- -- | Reports the distance from this agent to the point (xcor, ycor). 
-- distancexy :: TurtlePatch s => Double -> Double -> C s _s' m Double

-- | Reports the heading from this agent to the given agent. 
towards :: (TurtlePatch a, TurtlePatch s) => a -> C s _s' m Double
towards = todo

-- -- | Reports an agentset that includes only those agents from the original agentset whose distance from the caller is less than or equal to number. This can include the agent itself.
-- in_radius :: (TurtlePatch a, TurtlePatch s) => [a] -> Double -> C s _s' m [a]

{-# SPECIALIZE INLINE link :: Int -> Int -> C _s _s' STM Link #-}
{-# SPECIALIZE INLINE link :: Int -> Int -> C _s _s' IO Link #-}
-- | Given the who numbers of the endpoints, reports the link connecting the turtles. If there is no such link reports nobody. To refer to breeded links you must use the singular breed form with the endpoints. 
link :: STMorIO m => Int -> Int -> C _s _s' m Link
link f t = liftM (fromMaybe (error "nobody") . M.lookup (f,t)) $ readTVarSI __links

{-# SPECIALIZE  links :: C _s _s' STM Links #-}
{-# SPECIALIZE  links :: C _s _s' IO Links #-}
-- | Reports the agentset consisting of all links. 
links :: STMorIO m => C _s _s' m Links
links = liftM (M.fromDistinctAscList . nubBy checkForUndirected) $ (liftM M.toAscList $ readTVarSI __links)
        where
          checkForUndirected (_,(MkLink {end1_ = e1, end2_ = e2, directed_ = False})) (_,(MkLink {end1_ = e1', end2_ = e2', directed_ = False})) = (e1 == e2' && e1' == e2) || (e1==e1' && e2==e2')
          checkForUndirected _ _ = False



--{-# WARNING towards "TODO: wrapping" #-}

--   distance [PatchRef (x,y) _] = distancexy (fromIntegral x) (fromIntegral y)
--   distance [TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty})] = do
--     x <- lift $ readTVar tx
--     y <- lift $ readTVar ty
--     distancexy x y
--   distance _ = throw $ TypeException "single turtle or patch" Nobody

--   distancexy x' y' = do
--     (a,_) <- RWS.ask
--     (x,y) <- case a of
--               PatchRef (x,y) _ -> return (fromIntegral x, fromIntegral y)
--               TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty}) -> liftM2 (,) (lift $ readTVar tx) (lift $ readTVar ty)
--               _ -> throw $ ContextException "turtle or patch" a
--     return $ sqrt (deltaX x x' ^ 2 + 
--                 deltaY y y' ^ 2)
--     where
--       deltaX a1 a2 = if horizontal_wrap_ cmdOpt
--                      then min 
--                               (abs (a2 - a1))
--                               (abs (a2 - (fromIntegral $ max_pxcor_ cmdOpt) - a1 + (fromIntegral $ min_pxcor_ cmdOpt) + 1))
--                      else abs (a2 -a1)
--       deltaY a1 a2 = if vertical_wrap_ cmdOpt
--                      then min 
--                               (abs (a2 - a1)) 
--                               (abs (a2 - (fromIntegral $ max_pycor_ cmdOpt) - a1 + (fromIntegral $ min_pycor_ cmdOpt) + 1))
--                      else abs (a2 -a1)

--   towards a = do
--     (s,_) <- RWS.ask
--     (x1,y1) <- case s of
--               PatchRef (x,y) _ -> return (fromIntegral x, fromIntegral y)
--               TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty}) -> do
--                      x <- lift $ readTVar tx
--                      y <- lift $ readTVar ty
--                      return (x,y)
--               _ -> throw $ ContextException "turtle or patch" s
--     (x2,y2) <- case a of
--                 [PatchRef (x,y) _] -> return (fromIntegral x, fromIntegral y)
--                 [TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty})] -> do
--                      x <- lift $ readTVar tx
--                      y <- lift $ readTVar ty
--                      return (x,y)
--                 _ -> throw $ ContextException "turtle or patch" (head a)
--     let dx' = x2 - x1
--     let dy' = y2 - y1
--     return $ if dx' == 0
--               then
--                   if dy' > 0 
--                   then 0 
--                   else 180
--               else
--                   if dy' == 0
--                   then if dx' > 0 
--                        then 90 
--                        else 270
--                   else (270 + toDegrees (pi + atan2 (-dy') dx')) `mod_` 360

--   in_radius as n = do
--     (a,_) <- RWS.ask
--     (x, y) <- case a of
--                PatchRef (x,y) _ -> return (fromIntegral x, fromIntegral y)
--                TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty}) -> liftM2 (,) (lift $ readTVar tx) (lift $ readTVar ty)
--                _ -> throw $ ContextException "turtle or patch" a
--     filterM (\ (TurtleRef _ (MkTurtle {xcor_ = tx', ycor_ = ty'})) -> do 
--                x' <- lift $ readTVar tx'
--                y' <- lift $ readTVar ty'
--                return $ sqrt (delta x x' (fromIntegral (max_pxcor_ cmdOpt) :: Int) ^ (2::Int) + 
--                            delta y y' (fromIntegral (max_pycor_ cmdOpt) :: Int) ^ (2::Int)) <= n) as


--   distance [PatchRef (x,y) _] = distancexy (fromIntegral x) (fromIntegral y)
--   distance [TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty})] = do
--     x <- lift $ readTVarIO tx
--     y <- lift $ readTVarIO ty
--     distancexy x y
--   distance _ = throw $ ContextException "single turtle or patch" Nobody


--   distancexy x' y' = do
--     (a,_) <- RWS.ask
--     (x,y) <- case a of
--               PatchRef (x,y) _ -> return (fromIntegral x, fromIntegral y)
--               TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty}) -> liftM2 (,) (lift $ readTVarIO tx) (lift $ readTVarIO ty)
--               _ -> throw $ ContextException "turtle or patch" a
--     return $ sqrt (deltaX x x' ^ 2 + 
--                 deltaY y y' ^ 2)
--     where
--       deltaX a1 a2 = if horizontal_wrap_ cmdOpt
--                      then min 
--                               (abs (a2 - a1))
--                               (abs (a2 - fromIntegral (max_pxcor_ cmdOpt) - a1 + fromIntegral (min_pxcor_ cmdOpt) + 1))
--                      else abs (a2 -a1)
--       deltaY a1 a2 = if vertical_wrap_ cmdOpt
--                      then min 
--                               (abs (a2 - a1)) 
--                               (abs (a2 - fromIntegral (max_pycor_ cmdOpt) - a1 + fromIntegral (min_pycor_ cmdOpt) + 1))
--                      else abs (a2 -a1)

--   towards a = do
--     (s,_) <- RWS.ask
--     (x1,y1) <- case s of
--               PatchRef (x,y) _ -> return (fromIntegral x, fromIntegral y)
--               TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty}) -> do
--                      x <- lift $ readTVarIO tx
--                      y <- lift $ readTVarIO ty
--                      return (x,y)
--               _ -> throw $ ContextException "turtle or patch" s
--     (x2,y2) <- case a of
--                 [PatchRef (x,y) _] -> return (fromIntegral x, fromIntegral y)
--                 [TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty})] -> do
--                      x <- lift $ readTVarIO tx
--                      y <- lift $ readTVarIO ty
--                      return (x,y)
--                 _ -> throw $ ContextException "turtle or patch" (head a)
--     let dx' = x2 - x1
--     let dy' = y2 - y1
--     return $ if dx' == 0
--               then
--                   if dy' > 0 
--                   then 0 
--                   else 180
--               else
--                   if dy' == 0
--                   then if dx' > 0 
--                        then 90 
--                        else 270
--                   else (270 + toDegrees (pi + atan2 (-dy') dx')) `mod_` 360

--   in_radius as n = do
--     (a,_) <- RWS.ask
--     (x, y) <- case a of
--       PatchRef (x,y) _ -> return (fromIntegral x, fromIntegral y)
--       TurtleRef _ (MkTurtle {xcor_ = tx, ycor_ = ty}) -> liftM2 (,) (lift $ readTVarIO tx) (lift $ readTVarIO ty)
--       _ -> throw $ ContextException "turtle or patch" a
--     with (distancexy x y >>= \ d -> return $ d <= n) as


-- | Reports a shade of color proportional to the value of number. 
scale_color :: STMorIO m => Double -> C _s _s' m Double -> Double -> Double -> C _s _s' m Double
scale_color c v minArg maxArg = do
  let c' = findCentralColorNumber c - 5.0
  var <- v
  let perc | minArg > maxArg = if var < maxArg
                               then 1
                               else if var > minArg
                                    then 0
                                    else (minArg - var) / (minArg - maxArg)
           | var > maxArg =1 
           | var < minArg = 0
           | otherwise = (var - minArg) / (maxArg - minArg)
  return $ c' + let perc' = perc * 10
                in if perc' >= 9.9999
                   then 9.9999
                   else if perc' < 0
                        then 0
                        else perc'
    where
      -- | Internal
      findCentralColorNumber :: Double -> Double
      findCentralColorNumber c = (fromIntegral (truncate (modulateDouble c / 10) :: Int) + 0.5) * 10
      -- | Internal
      -- It has bug with mod_ truncate
      modulateDouble :: Double -> Double
      modulateDouble c = 
        if c < 0 || c >= maxColor
        then 
          let c' = c `mod_` truncate maxColor
          in if c'<0
             then 
              let c'' = c' + maxColor
              in if c'' >= maxColor
                 then 139.9999999999999
                 else c''
             else  c'
        else c
            where maxColor = 140 :: Double

-- | Tells each patch to give equal shares of (number * 100) percent of the value of patch-variable to its eight neighboring patches. number should be between 0 and 1. Regardless of topology the sum of patch-variable will be conserved across the world. (If a patch has fewer than eight neighbors, each neighbor still gets an eighth share; the patch keeps any leftover shares.) 
-- can be done better, in a single sequential atomic
-- diffuse :: CSTM Double -> (Double -> CSTM ()) -> Double -> C Observer () IO ()
-- diffuse gettervar settervar perc = ask (do
--                           ns <- neighbors
--                           cns <- count ns
--                           g <- atomic gettervar
--                           let pg = g * perc / 8
--                           ask (atomic (do
--                                ng <- gettervar
--                                settervar (ng + pg))) ns
--                           atomic $ settervar (g - (pg * fromIntegral cns))
--                         ) =<< patches

-- Specialization trick to reduce the cost of using a class (STMorIO)
-- The downside is executable with bigger code

-- {-# SPECIALIZE  distance :: [AgentRef] -> CSTM Double #-}
-- {-# SPECIALIZE  distance :: [AgentRef] -> CIO Double #-}
-- {-# SPECIALIZE  distancexy :: Double -> Double -> CSTM Double #-}
-- {-# SPECIALIZE  distancexy :: Double -> Double -> CIO Double #-}
-- {-# SPECIALIZE  towards :: [AgentRef] -> CSTM Double #-}
-- {-# SPECIALIZE  towards :: [AgentRef] -> CIO Double #-}
-- {-# SPECIALIZE  in_radius :: [AgentRef] -> Double -> CSTM [AgentRef] #-}
-- {-# SPECIALIZE  in_radius :: [AgentRef] -> Double -> CIO [AgentRef] #-}




-- | A class to allow certain NetLogo builtin primitives to be used
-- both 'atomic'-wrapped as well without atomic, since their semantics are preserved. 
--
-- Mostly applies to Observer and IO-related commands. Also the implementation takes advantage of the faster 'readTVarIO'. 
-- The correct lifting (STM or IO) is left to type inference.
class Monad m => STMorIO m where
    readTVarSI :: TVar a -> C s _s' m a
    -- | Reports the current value of the tick counter. The result is always a number and never negative. 
    ticks :: C _s _s' m Double

    timer ::  C _s _s' m Double
    reset_timer :: C _s _s' m ()
    -- | Prints value in the Command Center, preceded by this agent, and followed by a carriage return.
    --
    -- HLogo-specific: There are no guarantees on which agent will be prioritized to write on the stdout. The only guarantee is that in case of show inside an 'atomic' transaction, no 'show' will be repeated if the transaction is retried. Compared to 'unsafe_show', the output is not mangled.
    show :: (Show s, Show a) => a -> C s _s' m ()
    -- | Prints value in the Command Center, followed by a carriage return. 
    --
    -- HLogo-specific: There are no guarantees on which agent will be prioritized to write on the stdout. The only guarantee is that in case of print inside an 'atomic' transaction, no 'print' will be repeated if the transaction is retried. Compared to 'unsafe_print', the output is not mangled.
    print :: Show a => a -> C _s _s' m ()


{-# WARNING timer "safe, but some might considered it unsafe with respect to STM, since it may poll the clock multiple times. The IO version of it is totally safe" #-}
{-# WARNING reset_timer "safe, but some might considered it unsafe with respect to STM, since it may poll the clock multiple times. The IO version of it is totally safe" #-}


instance STMorIO STM where
    readTVarSI = lift . readTVar

    ticks = lift $ unsafeIOToSTM $ readIORef __tick

    timer = lift $ realToFrac <$> (diffUTCTime <$> unsafeIOToSTM getCurrentTime <*> readTVar __timer)

    reset_timer = lift $ writeTVar __timer =<< unsafeIOToSTM getCurrentTime

    show a = do
      (s,_,_) <- Reader.ask
      lift $ writeTQueue __printQueue $ Prelude.show s ++ ": " ++ Prelude.show a

    print = lift . writeTQueue __printQueue . Prelude.show

instance STMorIO IO where
    readTVarSI = lift . readTVarIO

    ticks = lift $ readIORef __tick

    timer = lift $ realToFrac <$> (diffUTCTime <$> getCurrentTime <*> readTVarIO __timer)

    reset_timer = lift $ (atomically . writeTVar __timer) =<< getCurrentTime
      
    show a = do
      (s,_,_) <- Reader.ask
      lift $ atomically $ writeTQueue __printQueue $ Prelude.show s ++ ": " ++ Prelude.show a

    print = lift . (atomically . writeTQueue __printQueue) . Prelude.show


{-# RULES "print/ObserverIO" print = printObserverIO #-}
{-# RULES "print/ObserverSTM" print = printObserverSTM #-}
printObserverIO :: Show a => a -> C Observer b IO ()
printObserverIO = lift . Prelude.print
printObserverSTM :: Show a => a -> C Observer b STM ()
printObserverSTM a = lift $ unsafeIOToSTM $ Prelude.print a -- it is ok that observer unsafe-prints, because when it runs, it is the only agent running.

{-# RULES "show/ObserverIO" show = showObserverIO #-}
{-# RULES "show/ObserverSTM" show = showObserverSTM #-}
showObserverIO :: Show a => a -> C Observer b IO ()
showObserverIO a = lift $ Prelude.putStrLn ("observer: " ++ Prelude.show a)
showObserverSTM :: Show a => a -> C Observer b STM ()
showObserverSTM a = lift $ unsafeIOToSTM $ Prelude.putStrLn ("observer: " ++ Prelude.show a)


{-# SPECIALIZE INLINE ticks :: C _s _s' STM Double #-}
{-# SPECIALIZE INLINE ticks :: C _s _s' IO Double #-}
{-# SPECIALIZE INLINE timer :: C _s _s' STM Double #-}
{-# SPECIALIZE INLINE timer :: C _s _s' IO Double #-}
{-# SPECIALIZE INLINE reset_timer :: C _s _s' STM () #-}
{-# SPECIALIZE INLINE reset_timer :: C _s _s' IO () #-}
{-# SPECIALIZE INLINE show :: (Show s, Show a) => a -> C s _s' STM () #-}
{-# SPECIALIZE INLINE show :: (Show s, Show a) => a -> C s _s' IO () #-}
{-# SPECIALIZE INLINE print :: Show a => a -> C _s _s' STM () #-}
{-# SPECIALIZE INLINE print :: Show a => a -> C _s _s' IO () #-}
