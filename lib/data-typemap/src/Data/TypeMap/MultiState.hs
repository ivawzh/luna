{-# LANGUAGE UndecidableInstances #-}

module Data.TypeMap.MultiState where

import Prologue

import qualified Control.Monad.State.Layered as State
import qualified Data.TypeMap.Strict         as TypeMap
import qualified Type.Data.List              as List

import Control.Monad.State.Layered (StateT)
import Data.TypeMap.Strict         (TypeMap)


------------------------
-- === MultiState === --
------------------------

-- === Definition === --

newtype MultiStateT (s :: [Type]) m a = MultiStateT (StateT (TypeMap s) m a)
    deriving ( Applicative, Alternative, Functor, Monad, MonadFail, MonadFix
             , MonadIO, MonadPlus, MonadThrow, MonadTrans)
makeLenses ''MultiStateT


-- === API === --

runT  ::              MultiStateT s m a -> TypeMap s -> m (a, TypeMap s)
execT :: Functor m => MultiStateT s m a -> TypeMap s -> m (TypeMap s)
evalT :: Functor m => MultiStateT s m a -> TypeMap s -> m a
runT  = State.runT  . unwrap ; {-# INLINE runT  #-}
execT = State.execT . unwrap ; {-# INLINE execT #-}
evalT = State.evalT . unwrap ; {-# INLINE evalT #-}


-- === State instances === --

instance (elem ~ List.In a s, Getter__ elem s m a)
      => State.Getter a (MultiStateT s m) where
    get = get__ @elem ; {-# INLINE get #-}

instance (elem ~ List.In a s, Setter__ elem s m a)
      => State.Setter a (MultiStateT s m) where
    put = put__ @elem ; {-# INLINE put #-}

class Monad m => Getter__ (elem :: Bool) s m a where
    get__ :: MultiStateT s m a

class Monad m => Setter__ (elem :: Bool) s m a where
    put__ :: a -> MultiStateT s m ()

instance (Monad m, State.Getter a m) => Getter__ 'False s m a where
    get__ = lift $ State.get @a ; {-# INLINE get__ #-}

instance (Monad m, State.Setter a m) => Setter__ 'False s m a where
    put__ = lift . State.put @a ; {-# INLINE put__ #-}

instance (Monad m, TypeMap.ElemGetter a s)
      => Getter__ 'True s m a where
    get__ = wrap $ TypeMap.getElem @a <$> State.get @(TypeMap s)
    {-# INLINE get__ #-}

instance (Monad m, TypeMap.ElemSetter a s)
      => Setter__ 'True s m a where
    put__ a = wrap $ State.modify_ @(TypeMap s) $ TypeMap.setElem @a a
    {-# INLINE put__ #-}
