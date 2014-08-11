{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs     #-}
module CLaSH.Signal.Explicit
  ( -- * Explicitly clocked synchronous signal
    -- $relativeclocks
    CSignal
    -- * Clock domain crossing
    -- ** Clock
  , Clock (..)
  , SClock (..)
  , sclock
  , SystemClock
  , systemClock
    -- ** Synchronisation primitive
  , veryUnsafeSynchronizer
    -- * Basic circuit functions
  , csignal
  , cregister
    -- * Product/Signal isomorphism
  , Wrap
  , Wrapped
  , cunwrap
  , cwrap
    -- * Simulation functions (not synthesisable)
  , csimulate
  , csimulateP
    -- * List \<-\> CSignal conversion (not synthesisable)
  , csample
  , csampleN
  , cfromList
  )
where

import GHC.TypeLits          (KnownNat, KnownSymbol)

import CLaSH.Promoted.Nat    (snat, snatToInteger)
import CLaSH.Promoted.Symbol (ssymbol)
import CLaSH.Signal.Internal (CSignal (..), Clock (..), SClock (..),
                              SystemClock, csignal)
import CLaSH.Signal.Wrap     (Wrap (..), Wrapped)

-- * Clock domain crossing
-- ** Clock
sclock :: (KnownNat period, KnownSymbol name)
       => SClock (Clk name period)
sclock = SClock ssymbol snat

systemClock :: SClock (Clk "system" 1000)
systemClock = sclock

-- ** Synchronisation primitive
{-# NOINLINE veryUnsafeSynchronizer #-}
veryUnsafeSynchronizer :: SClock clk1 -- ^ 'Clock' of the incoming signal
                       -> SClock clk2 -- ^ 'Clock' of the outgoing signal
                       -> CSignal clk1 a
                       -> CSignal clk2 a
veryUnsafeSynchronizer (SClock _ period1) (SClock _ period2) s = s'
  where
    t1    = fromInteger (snatToInteger period1)
    t2    = fromInteger (snatToInteger period2)
    s' | t1 < t2   = compress   t2 t1 s
       | t1 > t2   = oversample t1 t2 s
       | otherwise = same s

same :: CSignal clk1 a -> CSignal clk2 a
same (s :- ss) = s :- same ss

oversample :: Int -> Int -> CSignal clk1 a -> CSignal clk2 a
oversample high low (s :- ss) = s :- oversampleS (reverse (repSchedule high low)) ss

oversampleS :: [Int] -> CSignal clk1 a -> CSignal clk2 a
oversampleS sched = oversample' sched
  where
    oversample' []     s       = oversampleS sched s
    oversample' (d:ds) (s:-ss) = prefixN d s (oversample' ds ss)

    prefixN 0 _ s = s
    prefixN n x s = x :- prefixN (n-1) x s

compress :: Int -> Int -> CSignal clk1 a -> CSignal clk2 a
compress high low s = compressS (repSchedule high low) s

compressS :: [Int] -> CSignal clk1 a -> CSignal clk2 a
compressS sched = compress' sched
  where
    compress' []     s           = compressS sched s
    compress' (d:ds) ss@(s :- _) = s :- compress' ds (dropS d ss)

    dropS 0 s         = s
    dropS n (_ :- ss) = dropS (n-1) ss

repSchedule :: Int -> Int -> [Int]
repSchedule high low = take low $ repSchedule' low high 1
  where
    repSchedule' cnt th rep
      | cnt < th  = repSchedule' (cnt+low) th (rep + 1)
      | otherwise = rep : repSchedule' (cnt + low) (th + high) 1

-- * Basic circuit functions
{-# NOINLINE cregister #-}
cregister :: SClock clk -> a -> CSignal clk a -> CSignal clk a
cregister _ a s = a :- s

-- * Product/Signal isomorphism
cunwrap :: Wrap a => SClock clk -> Wrapped clk a -> CSignal clk a
cunwrap = unwrap

cwrap :: Wrap a => SClock clk -> CSignal clk a -> Wrapped clk a
cwrap = wrap

-- * Simulation functions
csimulate :: (CSignal clk1 a -> CSignal clk2 b) -> [a] -> [b]
csimulate f = csample . f . cfromList

-- | Simulate a (@'CSignalP' clk1 a -> 'CSignalP' clk2 b@) function given a list
-- of samples of type @a@
--
-- > clk100 = Clock d100
--
-- >>> csimulateP clk100 clk100 (cunpack clk100 . cregister clk100 (8,8) . cpack clk100) [(1,1), (2,2), (3,3), ...
-- [(8,8), (1,1), (2,2), (3,3), ...
csimulateP :: (Wrap a, Wrap b)
           => SClock clk1 -- ^ 'Clock' of the incoming signal
           -> SClock clk2 -- ^ 'Clock' of the outgoing signal
           -> (Wrapped clk1 a -> Wrapped clk2 b) -- ^ Function to simulate
           -> [a] -> [b]
csimulateP clk1 clk2 f = csimulate (cunwrap clk2 . f . cwrap clk1)

-- * List \<-\> CSignal conversion
csample :: CSignal clk a -> [a]
csample ~(s :- ss) = s : csample ss

csampleN :: Int -> CSignal clk a -> [a]
csampleN 0 _          = []
csampleN n ~(s :- ss) = s : csampleN (n-1) ss

cfromList :: [a] -> CSignal clk a
cfromList []     = error "finite list"
cfromList (s:ss) = s :- cfromList ss
