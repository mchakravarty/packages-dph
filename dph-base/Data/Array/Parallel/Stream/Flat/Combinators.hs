-----------------------------------------------------------------------------
-- |
-- Module      : Data.Array.Parallel.Stream.Flat.Combinators
-- Copyright   : (c) 2006 Roman Leshchinskiy
-- License     : see libraries/ndp/LICENSE
-- 
-- Maintainer  : Roman Leshchinskiy <rl@cse.unsw.edu.au>
-- Stability   : internal
-- Portability : non-portable (existentials)
--
--
-- Higher-order combinators for streams
--

{-# LANGUAGE CPP #-}

#include "fusion-phases.h"

module Data.Array.Parallel.Stream.Flat.Combinators (
  mapS, filterS, foldS, fold1MaybeS, scanS, scan1S, mapAccumS,
  zipWithS, zipWith3S, zipS, zip3S, combineS, combine2ByTagS
) where

import Data.Array.Parallel.Base (
  (:*:)(..), MaybeS(..), Rebox(..) )
import Data.Array.Parallel.Base.DTrace
import Data.Array.Parallel.Stream.Flat.Stream



-- | Mapping
--
mapS :: (a -> b) -> Stream a -> Stream b
{-# INLINE_STREAM mapS #-}
mapS f (Stream next s n c) = Stream next' s n ("mapS" `sArgs` c)
  where
    {-# INLINE next' #-}
    next' s = case next s of
                Done       -> Done
                Skip    s' -> Skip s'
                Yield x s' -> Yield (f x) s'

-- | Filtering
--
filterS :: (a -> Bool) -> Stream a -> Stream a
{-# INLINE_STREAM filterS #-}
filterS f (Stream next s n c) = Stream next' s n ("filterS" `sArgs` c)
  where
    {-# INLINE next' #-}
    next' s = case next s of
                Done                    -> Done
                Skip s'                 -> Skip s'
                Yield x  s' | f x       -> Yield x s'
                            | otherwise -> Skip s'


-- | Folding
-- 
foldS :: Rebox b => (b -> a -> b) -> b -> Stream a -> b
{-# INLINE_STREAM foldS #-}
foldS f z (Stream next s _ c) = traceLoopEntry c' $ fold z s
  where
    fold z s = case next s of
                 Done       -> traceLoopExit c' z
                 Skip    s' -> z `dseq` s' `dseq` fold z s'
                 Yield x s' -> let z' = f z x
                               in s' `dseq` z' `dseq` fold z' s'

    c' = "foldS" `sArgs` c

-- | Yield 'NothingS' if the 'Stream' is empty and fold it otherwise.
--
fold1MaybeS :: Rebox a => (a -> a -> a) -> Stream a -> MaybeS a
{-# INLINE_STREAM fold1MaybeS #-}
fold1MaybeS f (Stream next s _ c) = traceLoopEntry c' $ fold0 s
  where
    fold0 s   = case next s of
                  Done       -> traceLoopExit c' NothingS
                  Skip    s' -> s' `dseq` fold0 s'
                  Yield x s' -> s' `dseq` fold1 x s'
    fold1 z s = case next s of
                  Done       -> traceLoopExit c' $ JustS z
                  Skip    s' -> s' `dseq` z `dseq` fold1 z s'
                  Yield x s' -> let z' = f z x
                                in s' `dseq` z' `dseq` fold1 z' s'

    c' = "fold1MaybeS" `sArgs` c

-- | Scanning
--
scanS :: Rebox b => (b -> a -> b) -> b -> Stream a -> Stream b
{-# INLINE_STREAM scanS #-}
scanS f z (Stream next s n c) = Stream next' (z :*: s) n ("scanS" `sArgs` c)
  where
    {-# INLINE next' #-}
    next' (z :*: s) = case next s of
                        Done -> Done
                        Skip s' -> Skip (z :*: s')
                        Yield x s'  -> Yield z (f z x :*: s')

-- | Scan over a non-empty 'Stream'
--
scan1S :: Rebox a => (a -> a -> a) -> Stream a -> Stream a
{-# INLINE_STREAM scan1S #-}
scan1S f (Stream next s n c) = Stream next' (NothingS :*: s) n ("scan1S" `sArgs` c)
  where
    {-# INLINE next' #-}
    next' (NothingS :*: s) =
      case next s of
        Yield x s' -> Yield x (JustS x :*: s')
        Skip    s' -> Skip    (NothingS :*: s')
        Done       -> Done

    next' (JustS z :*: s) =
      case next s of
        Yield x s' -> let y = f z x
                      in
                      Yield y (JustS y :*: s')
        Skip    s' -> Skip (JustS z :*: s)
        Done       -> Done

mapAccumS :: Rebox acc => (acc -> a -> acc :*: b) -> acc -> Stream a -> Stream b
{-# INLINE_STREAM mapAccumS #-}
mapAccumS f acc (Stream step s n c) = Stream step' (s :*: acc) n ("mapAccumS" `sArgs` c)
  where
    step' (s :*: acc) = case step s of
                          Done -> Done
                          Skip s' -> Skip (s' :*: acc)
                          Yield x s' -> let acc' :*: y = f acc x
                                        in
                                        Yield y (s' :*: acc')


combineS:: Stream Bool -> Stream a -> Stream a -> Stream a
{-# INLINE_STREAM combineS #-}
combineS (Stream next1 s m c) (Stream nextS1 t1 n1 c1) (Stream nextS2 t2 n2 c2)
  = Stream next (s :*: t1 :*: t2) m ("combineS" `sArgs` (c,c1,c2))
  where
    {-# INLINE next #-}
    next (s :*: t1 :*: t2) = 
      case next1 s of
        Done -> Done
        Skip s'    -> Skip (s' :*: t1 :*: t2) 
        Yield c s' -> if  c  
                        then case nextS1 t1 of
                               Done        -> error "combineS: stream 1 terminated unexpectedly" 
                               Skip t1'    -> Skip (s :*: t1' :*: t2)
                               Yield x t1' -> Yield x (s' :*: t1' :*: t2)
                        else case nextS2 t2 of
                               Done        -> error "combineS: stream 2 terminated unexpectedly" 
                               Skip t2'    -> Skip (s :*: t1 :*: t2')
                               Yield x t2' -> Yield x (s' :*: t1 :*: t2')


combine2ByTagS :: Stream Int -> Stream a -> Stream a -> Stream a
{-# INLINE_STREAM combine2ByTagS #-}
combine2ByTagS (Stream next_tag s m c) (Stream next0 s0 _ c1)
                                       (Stream next1 s1 _ c2)
  = Stream next (NothingS :*: s :*: s0 :*: s1) m ("combine2ByTagS" `sArgs` (c,c1,c2))
  where
    {-# INLINE next #-}
    next (NothingS :*: s :*: s0 :*: s1)
      = case next_tag s of
          Done       -> Done
          Skip    s' -> Skip (NothingS :*: s' :*: s0 :*: s1)
          Yield t s' -> Skip (JustS t  :*: s' :*: s0 :*: s1)

    next (JustS 0 :*: s :*: s0 :*: s1)
      = case next0 s0 of
          Done        -> error "combine2ByTagS: stream 1 too short"
          Skip    s0' -> Skip    (JustS 0  :*: s :*: s0' :*: s1)
          Yield x s0' -> Yield x (NothingS :*: s :*: s0' :*: s1)

    next (JustS t :*: s :*: s0 :*: s1)
      = case next1 s1 of
          Done        -> error "combine2ByTagS: stream 2 too short"
          Skip    s1' -> Skip    (JustS t  :*: s :*: s0 :*: s1')
          Yield x s1' -> Yield x (NothingS :*: s :*: s0 :*: s1')

-- | Zipping
--

-- FIXME: The definition below duplicates work if the second stream produces
-- Skips. Unfortunately, GHC tends to introduce join points which break
-- SpecConstr with the correct definition.
zipWithS :: (a -> b -> c) -> Stream a -> Stream b -> Stream c
{-# INLINE_STREAM zipWithS #-}
zipWithS f (Stream next1 s m c1) (Stream next2 t n c2) =
  Stream next (s :*: t) m ("zipWithS" `sArgs` (c1,c2))
  where
    {-# INLINE next #-}
    next (s :*: t) =
      case next1 s of
        Done -> Done
        Skip s' -> Skip (s' :*: t)
        Yield x s' -> case next2 t of
                        Done -> Done
                        Skip t' -> Skip (s :*: t')
                        Yield y t' -> Yield (f x y) (s' :*: t')

{-  Stream next (NothingS :*: s :*: t) m
  where
    {-# INLINE next #-}
    next (NothingS :*: s :*: t) =
      t `seq`
      case next1 s of
        Done       -> Done
        Skip    s' -> Skip (NothingS :*: s' :*: t)
        Yield x s' -> -- Skip (JustS x  :*: s' :*: t)
                      case next2 t of
                        Done       -> Done
                        Skip    t' -> Skip (JustS (Box x) :*: s' :*: t')
                        Yield y t' -> Yield (f x y) (NothingS :*: s' :*: t')
    next (JustS (Box x) :*: s :*: t) =
      s `seq`
      case next2 t of
        Done       -> Done
        Skip t'    -> Skip (JustS (Box x) :*: s :*: t')
        Yield y t' -> Yield (f x y) (NothingS :*: s :*: t')
-}

{-# RULES

"zipWithS[s,s]" forall f s.
  zipWithS f s s = mapS (\x -> f x x) s

 #-}

zipWith3S :: (a -> b -> c -> d) -> Stream a -> Stream b -> Stream c -> Stream d
{-# INLINE_STREAM zipWith3S #-}
zipWith3S f (Stream next1 s1 n c1) (Stream next2 s2 _ c2) (Stream next3 s3 _ c3)
  = Stream next (s1 :*: s2 :*: s3) n ("zipWith3S" `sArgs` (c1,c2,c3))
  where
    {-# INLINE next #-}
    next (s1 :*: s2 :*: s3) =
      case next1 s1 of
        Done         -> Done
        Skip s1' -> Skip (s1' :*: s2 :*: s3)
        Yield x s1'  ->
          case next2 s2 of
            Done         -> Done
            Skip s2' -> Skip (s1 :*: s2' :*: s3)
            Yield y s2'  ->
              case next3 s3 of
                Done         -> Done
                Skip s3' -> Skip (s1 :*: s2 :*: s3')
                Yield z s3'  -> Yield (f x y z) (s1' :*: s2' :*: s3')

zipS :: Stream a -> Stream b -> Stream (a :*: b)
{-# INLINE zipS #-}
zipS = zipWithS (:*:)

zip3S :: Stream a -> Stream b -> Stream c -> Stream (a :*: b :*: c)
{-# INLINE zip3S #-}
zip3S = zipWith3S (\x y z -> x :*: y :*: z)

