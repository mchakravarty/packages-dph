{-# LANGUAGE ParallelArrays, ParallelListComp #-}
{-# OPTIONS -fvectorise #-}

module Vectorised
    (solvePA)
where

import CommonVectorised
import Data.Array.Parallel hiding ((+), (-), (*), (/))
import Data.Array.Parallel.PArray
import Data.Array.Parallel.Prelude.Bool
import Data.Array.Parallel.Prelude.Double        as D
import qualified Data.Array.Parallel.Prelude.Int as I
import qualified Prelude    as P


{-# NOINLINE solvePA #-}
solvePA
    :: PArray Vec3           -- ^ vertices of the surface
    -> PArray (Int,Int,Int)  -- ^ triangles, each 3 vertex indices
    -> PArray Vec3           -- ^ rays to cast
    -> PArray (Vec3,Double)  -- ^ rays and their distance
solvePA vertices triangles rays
 = toPArrayP (solveV (fromPArrayP vertices) (fromPArrayP triangles) (fromPArrayP rays))

solveV 
    :: [:Vec3:]             -- ^ vertices of the surface
    -> [:(Int,Int,Int):]    -- ^ triangles, each 3 vertex indices
    -> [:Vec3:]             -- ^ rays to cast
    -> [:(Vec3,Double):]    -- ^ rays and their distance
solveV vertices triangles rays
 = mapP cast' rays
 where
  cast' = cast vertices triangles


cast 
    :: [:Vec3:]          -- ^ vertices of the surface
    -> [:(Int,Int,Int):] -- ^ triangles, each 3 vertex indices
    -> Vec3              -- ^ ray
    -> (Vec3,Double)
cast vertices triangles ray
 = let r' = ((0,0,0), ray)
       pl = plueckerOfLine r'
       mi = minimumP
            (mapP (\t -> check r' pl (tri vertices t)) triangles)
   in  (ray, mi)

check r pl t
  | inside pl t = lineOnTriangle r t
  | otherwise = 1e100

tri :: [:Vec3:] -> (Int,Int,Int) -> Triangle
tri v (a,b,c) = (v !: a, v !: b, v !: c)