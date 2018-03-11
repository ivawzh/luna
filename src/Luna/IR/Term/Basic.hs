{-# LANGUAGE CPP                  #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeInType           #-}
{-# LANGUAGE UndecidableInstances #-}

module Luna.IR.Term.Basic where

import Prologue hiding (cast)

import           Foreign.Ptr            (Ptr, castPtr, plusPtr)
import           Foreign.Storable       (Storable, alignment, peek, peekByteOff,
                                         poke, pokeByteOff, sizeOf)
import qualified Foreign.Storable       as Storable
import           Foreign.Storable.Utils (alignment', castPtrTo, intPtr, sizeOf')
import qualified Foreign.Storable1      as Storable1

import qualified Data.Graph          as Graph
import qualified Foreign             as Ptr
import qualified Foreign.Memory.Pool as MemPool

import Foreign.Storable.Deriving  (deriveStorable)
import Foreign.Storable1.Deriving (deriveStorable1)

import           Luna.IR.Term (Model, Term, TermCons, Terms)
import qualified Luna.IR.Term as Term
-- import qualified OCI.IR.Layout as Layout
import Luna.IR.Link as Link

import           Data.Tag       (Tag, TagOf)
import           Luna.IR.Format
import qualified Luna.IR.Link   as Link

import           Control.Monad.State.Layered (get, put)
import qualified Control.Monad.State.Layered as State
import qualified Data.Mutable                as MData
import qualified Data.Tag                    as Tag
import           OCI.IR.Component
import qualified OCI.IR.Component            as Component
import           OCI.IR.Conversion

import qualified Data.Tuple.Strict   as Tuple
import qualified Data.TypeMap.Strict as TypeMap

import           OCI.IR.Layout ((:=), Layout)
import qualified OCI.IR.Layout as Layout

import OCI.Pass.TH

-- import Control.Monad.State.Strict hiding (pure, liftIO, MonadIO)

import Foreign.Marshal.Alloc (mallocBytes)
import Type.Data.Ord         (Cmp)

import Foreign.Ptr.Utils (SomePtr)

import OCI.Pass.Class as Pass

import qualified Data.Map as Map

import Luna.IR.Term.TH
import Type.Cache

import           OCI.Pass.Manager (MonadPassManager)
import qualified OCI.Pass.Manager as PassManager

import qualified Control.Monad.Exception as Exception
import           Type.Data.Bool

-- import OCI.IR.Layer (Layer)
import qualified Foreign.Marshal.Utils as Mem
import qualified OCI.IR.Layer          as Layer
import qualified OCI.IR.Layer.Internal as Layer

-- import qualified OCI.IR.Layer2 as Layer2
import Luna.IR.Layout



type src *-* tgt = Layout [Source := src, Target := tgt]

----------------
-- === IR === --
----------------

-- === IR Atoms === ---


Tag.familyInstance "TermCons" "Var"
newtype ConsVar a = Var
    { __name :: Int
    } deriving (Show, Eq)
type instance Term.TagToCons Var     = ConsVar
type instance Term.ConsToTag ConsVar = Var
makeLenses           ''ConsVar
deriveStorable       ''ConsVar
deriveStorable1      ''ConsVar
deriveLinksDiscovery ''ConsVar

Tag.familyInstance "TermCons" "Acc"
data ConsAcc a = Acc
    { __base :: !(Link (Layout.Get Terms a *-* Layout.Set Model Acc a)) -- !(Link.Term Acc a)
    , __name :: !(Link (Layout.Get Names a *-* Layout.Set Model Acc a)) -- !(Link.Name Acc a)
    } deriving (Show, Eq)
type instance Term.TagToCons Acc     = ConsAcc
type instance Term.ConsToTag ConsAcc = Acc
makeLenses           ''ConsAcc
deriveStorable       ''ConsAcc
deriveStorable1      ''ConsAcc
deriveLinksDiscovery ''ConsAcc

Tag.familyInstance "TermCons" "Missing"
data ConsMissing a = Missing deriving (Show, Eq)
type instance Term.TagToCons Missing     = ConsMissing
type instance Term.ConsToTag ConsMissing = Missing
makeLenses           ''ConsMissing
deriveStorable       ''ConsMissing
deriveStorable1      ''ConsMissing
deriveLinksDiscovery ''ConsMissing

data UniTerm a
    = UniTermVar     !(ConsVar     a)
    | UniTermAcc     !(ConsAcc     a)
    | UniTermMissing !(ConsMissing a)
    deriving (Show, Eq)
makeLenses           ''UniTerm
deriveStorable       ''UniTerm
deriveStorable1      ''UniTerm
deriveLinksDiscovery ''UniTerm

type instance Term.Uni = UniTerm

instance Term.IsUni ConsVar     where toUni = UniTermVar     ; {-# INLINE toUni #-}
instance Term.IsUni ConsAcc     where toUni = UniTermAcc     ; {-# INLINE toUni #-}
instance Term.IsUni ConsMissing where toUni = UniTermMissing ; {-# INLINE toUni #-}



-- === Smart constructors === --

#define CTX(name) (Term.Creator name m, LinkCreator m)

var :: CTX(Var) => Int -> m (Term Var)
var = Term.uncheckedNew . Var ; {-# INLINE var #-}

missing :: CTX(Missing) => m (Term Missing)
missing = Term.uncheckedNew Missing ; {-# INLINE missing #-}

acc :: CTX(Acc) => Term base -> Term name -> m (Term (Acc -* base -# name))
acc base name = Term.newM $ \term -> Acc <$> link base term <*> link name term ; {-# INLINE acc #-}

#undef CTX




type instance Layer.Data   Terms Type = Link
-- type instance Layer.Layout Terms Type layout = layout *-* Layout.Get Type layout
type instance Layer.Layout Terms Type layout = layout *-* layout

instance Layer.Initializer Terms Type where
    init = Component.unsafeNull ; {-# INLINE init #-}



-- type instance Layer.ConsData Terms Model (TermCons f) = Term.TagToCons (TermCons f)



-- type instance Layer     Terms Type   =
-- type instance Layer.View Terms Type a =
-- instance StorableLayer.View Terms Model (Format f)
-- instance Storable (Layer.View' Terms Model (TermCons f))
--     => StorableLayer.View Terms Model (TermCons f) where
--     peekLayer.ViewIO ptr = peek (ptr `plusPtr` constructorSize) ; {-# INLINE peekLayer.ViewIO #-}


type instance Layer.Layout Links Source layout = Layout.Get Source layout
type instance Layer.Layout Links Target layout = Layout.Get Target layout
type instance Layer.Data   Links Source        = Term
type instance Layer.Data   Links Target        = Term

instance Layer.Initializer Links Source where
    init = Component.unsafeNull ; {-# INLINE init #-}

instance Layer.Initializer Links Target where
    init = Component.unsafeNull ; {-# INLINE init #-}


instance Layer.Initializer Terms Model where
    init = UniTermMissing Missing ; {-# INLINE init #-}



type instance Cmp Model Terms = 'LT
type instance Cmp Terms Model = 'GT


type instance Cmp Model Names = 'LT
type instance Cmp Names Model = 'GT

type instance Cmp Names Terms = 'LT
type instance Cmp Terms Names = 'GT
-- class Reader layer where


-- data ConsAcc a = Acc
-- { __base :: !(Link (Layout.Get Terms a *-* Layout.Set Model Acc a)) -- !(Link.Term Acc a)
-- , __name :: !(Link (Layout.Get Names a *-* Layout.Set Model Acc a)) -- !(Link.Name Acc a)
-- } deriving (Show, Eq)


-- type T1 = Layout.FromList '[Terms := Int, Names := Char, Model := Acc]
-- type T2 = Layout.Set Model Acc T1

-- x :: Proxy T1
-- x = undefined
-- y :: Proxy T2
-- y = x




type LinkCreator m = (Component.Creator Links m, Layer.Writer Links Source m, Layer.Writer Links Target m)

link :: LinkCreator m
     => Term src -> Term tgt -> m (Link (src *-* tgt))
link src tgt = do
    ir <- Component.new
    Layer.write @Source ir src
    Layer.write @Target ir tgt
    pure $ ir
{-# INLINE link #-}





-- acc ::


-- Tag.familyInstance "TermCons" "Var"
-- newtype ConsVar a = Var
--     { __name :: Int
--     } deriving (Show, Eq)
-- type instance Term.TagToCons Var = ConsVar
-- type instance Layer.ConsLayout ConsVar = Var
-- deriveStorable ''ConsVar
-- deriveLinksDiscovery nsVar

-- newComponent :: forall t a m. (KnownLayers t, MonadIO m) => m (Component t a)
-- newComponent = Component . coerce <$> MemPool.allocBytes (totalLayersSize @t)


-- termMemPool, linkMemPool :: MemPool
-- termMemPool = unsafePerfromIO newMemPool ; {-# NOINLINE termMemPool #-}
-- linkMemPool = unsafePerfromIO newMemPool ; {-# NOINLINE linkMemPool #-}
--
--


-- type instance Layout.DefLayout layout (TermCons t) = Draft

data MyPass
type instance Spec MyPass t = Spec_MyPass t
type family   Spec_MyPass t where
    Spec_MyPass (In Elems) = '[Terms, Links]
    Spec_MyPass (In Terms) = '[Model, Type]
    Spec_MyPass (In Links) = '[Source, Target]
    Spec_MyPass (Out a)    = '[] -- Spec_MyPass (In a)
    Spec_MyPass t          = '[]

-- type instance PassStateLayout MyPass = ComputePassStateLayout MyPass
cachePassConfig_phase1 ''MyPass
cachePassConfig_phase2 ''MyPass



test_pm_run :: MonadIO m => m Pass.PassConfig
test_pm_run = Exception.catchAll undefined $ PassManager.evalT test_pm

test_pm :: (MonadPassManager m, MonadIO m) => m Pass.PassConfig
test_pm = do
    PassManager.registerComponent @Terms
    PassManager.registerPrimLayer @Terms @Model
    PassManager.registerPrimLayer @Terms @Type

    PassManager.registerComponent @Links
    PassManager.registerPrimLayer @Links @Source
    PassManager.registerPrimLayer @Links @Target

    reg <- State.get @PassManager.Registry
    passCfg <- PassManager.mkPassConfig reg

    pure passCfg


passTest :: Pass.Pass MyPass
passTest = do
    v1 <- var 5
    v2 <- var 7
    v3 <- var 9
    l1 <- link v1 v2

    Layer.write @Type v1 l1

    s <- Layer.read @Source l1
    m <- Layer.read @Model s
    print m
    pure ()

passTest_run :: IO ()
passTest_run = do

    cfg <- test_pm_run
    xx <- Pass.encodePassState cfg
    Pass.runPass xx passTest

--
-- passRunTest :: IO ()
-- passRunTest = do
--     mp <- MemPool.new 100
--     let cfg = Pass.PassConfig
--             $ Map.insert (someTypeRep @Terms)
--               (Pass.ComponentConfig 7
--                   ( Map.insert (someTypeRep @Model)
--                     (Pass.LayerConfig 11)
--                   $ mempty
--                   ) mp
--               )
--             $ mempty
--
--     xx <- Pass.encodePassState cfg
--     Pass.runPass xx passTest
-- runPass :: Functor m => PassState pass -> SubPass pass m a -> m a





--
-- type instance Pass.In AnyLayer Terms MyPass = '[Model]



mockNewComponent :: MonadIO m => m (Term Draft)
mockNewComponent = Component . coerce <$> MemPool.allocPtr @(UniTerm ()) ; {-# INLINE mockNewComponent #-}

mockNewLink :: forall m. MonadIO m => m (Link (Draft :-: Draft))
mockNewLink = undefined -- Component . coerce <$> MemPool.alloc @(LinkData Draft Draft)




layerLoc0 :: Int
layerLoc0 = 0 ; {-# INLINE layerLoc0 #-}

test :: IO ()
test = do
    var1 <- mockNewComponent
    var2 <- mockNewComponent
    acc1 <- mockNewComponent
    Layer.unsafeWriteByteOff @Model layerLoc0 var1 (UniTermVar $ Var 7)
    Layer.unsafeWriteByteOff @Model layerLoc0 var2 (UniTermVar $ Var 5)

    -- l1 <- mockNewLink
    -- Layer.unsafeWriteByteOff @Model layerLoc0 l1 (LinkData var1 acc1)

    -- Layer.unsafeWriteByteOff @Model layerLoc0 acc1 (UniTermAcc $ Acc l1 l1)

    -- print var1
    -- x <- Layer.unsafeReadByteOff @Model layerLoc0 var1
    -- print x




test_readWriteLayer :: Int -> IO ()
test_readWriteLayer i = do
    !ir <- mockNewComponent
    Layer.unsafeWriteByteOff @Model layerLoc0 ir (UniTermVar $ Var 0)
    let go 0 = pure ()
        go j = do
            UniTermVar (Var !y) <- Layer.unsafeReadByteOff @Model layerLoc0 ir
            UniTermVar (Var !z) <- Layer.unsafeReadByteOff @Model layerLoc0 ir
            UniTermVar (Var !x) <- Layer.unsafeReadByteOff @Model layerLoc0 ir
            Layer.unsafeWriteByteOff @Model layerLoc0 ir (UniTermVar $ Var $! x+1)
            go $! (j - 1)
    go i
    -- Ptr.free ptr

--
-- test_readWriteLayer2 :: Int -> IO ()
-- test_readWriteLayer2 i = do
--     ir <- mockNewComponent
--     writeLayer layerLoc0 ir (UniTermVar $ Var 0)
--     let -- go :: Int -> StateT Int IO ()
--         go 0 = pure ()
--         go j = do
--             set <- get'
--             let layer = TypeSet.unsafeLookup @(LayerLoc Model) set
--             Var x <- readLayer layer ir
--             writeLayer layer ir (Var (x+1))
--             go (j - 1)
--     State.evalT (go i)
--         $ TypeSet.insert (XInt 1)
--         $ TypeSet.insert (6 :: Int)
--         $ TypeSet.insert layerLoc0
--         $ mempty



test_readWriteLayer_ptrOff :: Int -> IO ()
test_readWriteLayer_ptrOff i = do
    -- ptr <- mallocBytes (sizeOf' @Int * _MAX_LAYERS)
    ptr <- Ptr.new (0 :: Int)
    ir <- mockNewComponent
    Layer.unsafeWriteByteOff @Model layerLoc0 ir (UniTermVar $ Var 0)
    let -- go :: Int -> StateT Int IO ()
        go 0 = pure ()
        go j = do
            -- set <- get'
            layer <- peek ptr
            UniTermVar (Var x) <- Layer.unsafeReadByteOff @Model layer ir
            Layer.unsafeWriteByteOff @Model layer ir (UniTermVar $ Var (x+1))
            go (j - 1)
    (go i)

_MAX_LAYERS :: Int
_MAX_LAYERS = 16

test_readWriteLayer_ptrBuffOff :: Int -> IO ()
test_readWriteLayer_ptrBuffOff i = do
    (ptr :: Ptr Int) <- mallocBytes (sizeOf' @Int * _MAX_LAYERS)
    poke ptr 0
    pokeByteOff ptr (sizeOf' @Int) (0 :: Int)
    pokeByteOff ptr (sizeOf' @Int * 2) (0 :: Int)
    pokeByteOff ptr (sizeOf' @Int * 3) (0 :: Int)
    pokeByteOff ptr (sizeOf' @Int * 4) (0 :: Int)
    pokeByteOff ptr (sizeOf' @Int * 5) (0 :: Int)
    pokeByteOff ptr (sizeOf' @Int * 6) (0 :: Int)
    pokeByteOff ptr (sizeOf' @Int * 7) (0 :: Int)
    ir <- mockNewComponent
    Layer.unsafeWriteByteOff @Model layerLoc0 ir (UniTermVar $ Var 0)
    let -- go :: Int -> StateT Int IO ()
        go 0 = pure ()
        go j = do
            p <- get @(Ptr Int)
            x <- get @Int
            put @Int (x+1)
            layer <- liftIO $ peek p
            UniTermVar (Var x) <- Layer.unsafeReadByteOff @Model layer ir
            Layer.unsafeWriteByteOff @Model layer ir (UniTermVar $ Var (x+1))
            go (j - 1)
    flip State.evalT (0::Int)
       $ flip State.evalT ptr (go i)

-- test_readWriteLayer_static :: Int -> IO ()
-- test_readWriteLayer_static i = do
--     ir <- mockNewComponent
--     writeLayer @Model ir (UniTermVar $ Var 0)
--     let -- go :: Int -> StateT Int IO ()
--         go 0 = pure ()
--         go j = do
--             UniTermVar (Var x) <- readLayer @Model ir
--             writeLayer @Model ir (UniTermVar $ Var (x+1))
--             go (j - 1)
--     (go i)

    -- State.evalT (go i)
    --     $ TypeSet.insert (XInt 1)
    --     $ TypeSet.insert (6 :: Int)
    --     $ TypeSet.insert layerLoc0
    --     $ mempty

    -- Ptr.free ptr

--
-- readWritePtr :: Int -> IO ()
-- readWritePtr i = do
--     ptr <- Ptr.new (0 :: Int)
--     let go 0 = pure ()
--         go j = do
--             x <- peek ptr
--             poke ptr (x+1)
--             go (j - 1)
--     go i
--     Ptr.free ptr




test_readWriteLayer2 :: Int -> IO ()
test_readWriteLayer2 i = do
    ir <- mockNewComponent
    Layer.unsafeWriteByteOff @Model layerLoc0 ir (UniTermVar $ Var 0)
    let -- go :: Int -> StateT Int IO ()
        go 0 = pure ()
        go j = do
            !set <- State.get'
            let !layer = TypeMap.getElem @Int set
            UniTermVar (Var !x) <- Layer.unsafeReadByteOff @Model layer ir
            Layer.unsafeWriteByteOff @Model layer ir (UniTermVar $ Var $! (x+1))
            go (j - 1)
    State.evalT (go i) (TypeMap.TypeMap (Tuple.T3 ('x' :: Char) ("a" :: String) (0 :: Int)) :: TypeMap.TypeMap '[Char, String, Int])
    -- Ptr.free ptr

-- test_readWriteLayer3 :: Int -> IO ()
-- test_readWriteLayer3 i = do
--     ir <- mockNewComponent
--     Layer.unsafeWriteByteOff @Model layerLoc0 ir (UniTermVar $ Var 0)
--     let -- go :: Int -> StateT Int IO ()
--         go :: Int -> Pass.Pass MyPass
--         go 0 = pure ()
--         go j = do
--             !s <- getPassState
--             Pass.LayerByteOffset !layer <- Pass.getData @(Pass.LayerByteOffset Terms Model)
--             UniTermVar (Var !x) <- Layer.unsafeReadByteOff @Model layer ir
--             Layer.unsafeWriteByteOff @Model layer ir (UniTermVar $ Var $! (x+1))
--             go (j - 1)
--
--     mp <- MemPool.new 100
--     let cfg = Pass.PassConfig
--             $ Map.insert (someTypeRep @Terms)
--               (Pass.ComponentConfig 0
--                   ( Map.insert (someTypeRep @Model)
--                     (Pass.LayerConfig 0)
--                   $ mempty
--                   ) mp
--               )
--             $ mempty
--     xx <- Pass.encodePassState cfg
--     Pass.runPass xx (go i)
    -- State.evalT (go i) (TypeMap.TypeMap (Tuple.T1 (0 :: Int)) :: TypeMap.TypeMap '[Int])


test_readWriteLayer4 :: Int -> IO ()
test_readWriteLayer4 i = do
    ir <- mockNewComponent
    Layer.unsafeWriteByteOff @Model layerLoc0 ir (UniTermVar $ Var 0)
    let go :: Int -> Pass.Pass MyPass
        go 0 = pure ()
        go j = do
            UniTermVar (Var !x) <- Layer.read @Model ir
            Layer.write @Model ir (UniTermVar $ Var $! (x+1))
            go (j - 1)

    cfg <- test_pm_run
    xx <- Pass.encodePassState cfg
    Pass.runPass xx (go i)
    -- State.evalT (go i) (TypeMap.TypeMap (Tuple.T1 (0 :: Int)) :: TypeMap.TypeMap '[Int])


test_mallocPtr :: Int -> IO ()
test_mallocPtr i = do
    let go !0 = pure ()
        go !j = do
            !ptr <- Ptr.new (0 :: Int)
            go $! j - 1
    go i


test_createNode :: Int -> IO ()
test_createNode i = do
    let go :: Int -> Pass.Pass MyPass
        go 0 = pure ()
        go j = do
            v <- var 5
            go (j - 1)

    cfg <- test_pm_run
    xx <- Pass.encodePassState cfg
    Pass.runPass xx (go i)


-- type instance Layout.GetBase Var = Var
tttest :: Term Var -> Pass.Pass MyPass
tttest n = do
    -- (x :: _) <- Layer.read @Model n
    -- (x :: _) <- Layer.readCons__ @Terms @Model n
    pure ()
-- unsafeReadByteOff  :: CTX => Int -> Component comp layout -> m (LayoutView comp layer layout)
-- #define CTX ∀ layer comp layout m. (StorableLayer comp layer layout, MonadIO m)

-- readLayer :: ∀ layer comp layout m. (Layer.StorableLayer comp layer layout, MonadIO m, Pass.PassDataGetter (Pass.LayerByteOffset comp layer) m)
--           => Component comp layout -> m (Layer.LayoutView comp layer layout)
-- readLayer comp = do
--     Pass.LayerByteOffset !off <- Pass.getData @(Pass.LayerByteOffset comp layer)
--     Layer.unsafeReadByteOff @layer off comp
-- {-# INLINE readLayer #-}
-- Pass.LayerByteOffset !layer <- Pass.getData @(Pass.LayerByteOffset Terms Model)
-- UniTermVar (Var !x) <- Layer.unsafeReadByteOff @Model layer ir








-- passTest :: Pass.Pass MyPass
-- passTest = do
--     s <- getPassState
--     print s
--     print =<< Pass.getData @(Pass.LayerByteOffset Terms Model)
--     pure ()
--
-- passRunTest :: IO ()
-- passRunTest = Pass.runPass (Pass.encodePassStateTEMP layout) passTest where
--     layout = Pass.PassConfig
--         $ Map.insert (someTypeRep @Terms)
--           (Pass.ComponentConfig 7
--               $ Map.insert (someTypeRep @Model)
--                 (Pass.LayerConfig 11)
--               $ mempty
--           )
--         $ mempty
    -- Ptr.free ptr
-- test_readWriteLayer2 :: Int -> IO ()
-- test_readWriteLayer2 i = do
--     ir <- mockNewComponent
--     Layer.unsafeWriteByteOff @Model layerLoc0 ir (UniTermVar $ Var 0)
--     let -- go :: Int -> StateT Int IO ()
--         go 0 = pure ()
--         go j = do
--             layer <- State.get'
--             -- let LayerLoc layer = TypeSet.unsafeLookup @(LayerLoc Model) set
--             UniTermVar (Var x) <- Layer.unsafeReadByteOff @Model layer ir
--             Layer.unsafeWriteByteOff @Model layer ir (UniTermVar $ Var (x+1))
--             go (j - 1)
--     State.evalT (go i) (0 :: Int)
--     -- State.evalT (go i) (TypeSet.insert (LayerLoc 0 :: LayerLoc Model) mempty)
--     -- Ptr.free ptr


-- test_readWriteLayer2 :: Int -> IO ()
-- test_readWriteLayer2 i = do
--     ir <- mockNewComponent
--     Layer.unsafeWriteByteOff @Model layerLoc0 ir (UniTermVar $ Var 0)
--     let -- go :: Int -> StateT Int IO ()
--         go 0 = pure ()
--         go j = do
--             set <- State.get'
--             let LayerLoc layer = TypeSet.unsafeLookup @(LayerLoc Model) set
--             UniTermVar (Var x) <- Layer.unsafeReadByteOff @Model layer ir
--             Layer.unsafeWriteByteOff @Model layer ir (UniTermVar $ Var (x+1))
--             go (j - 1)
--     State.evalT (go i) (TypeSet.insert (LayerLoc 0 :: LayerLoc Model) mempty)
--     -- Ptr.free ptr

-- Layer.unsafeWriteByteOff :: forall layer t layout m. (Layer t layer layout, MonadIO m) =>
--   Int -> Component t layout ->   (Layer.View t layer layout) -> m ()

-- readIO @Model

-- layerLoc0 = Layer (sizeOf' @)
-- newtype IRDef (layers :: [Type]) = IRDef (Ptr ()) deriving (Show)


-- newtype IR a = IR (IRDef '[])
-- class Layer l where



-- var :: Int -> IR Var



-- foo = do
--     let x = undefined :: Term Var
--         y = x
--         y :: Int
--     pure ()



-- newtype Term.TagToConsVar (a :: Layout) = Term.TagToConsVar
--     { __name :: Int
--     } deriving (Show, Eq)
-- type instance Term.TagToCons Var a = Term.TagToConsVar a

-- data IRDefVar (a :: Layout) = IRDefVar
--     { __type :: {-# UNPACK #-} !(Link.Type Var a)
--     , __term :: {-# UNPACK #-} !(Term.TagToConsVar a)
--     }




-- data Term.TagToConsAcc a = Term.TagToConsAcc
--     { __base :: !(Link.Term Acc a)
--     , __name :: !(Link.Name Acc a)
--     } deriving (Show, Eq)
-- type instance Term.TagToCons Acc a = Term.TagToConsAcc a

-- vvv - moze nie trzeba takich datatypow jezeli trzymalibysmy to w pamieci i skakli poitnerem robiac read @LayerName ?x
-- data IRDefAcc (a :: Layout) = IRDefAcc
--     { __type :: {-# UNPACK #-} !(Link.Type Acc a)
--     , __term :: {-# UNPACK #-} !(Term.TagToConsAcc a)
--     }

-- data family Term t (a :: Layout)
--
-- data instance Term (TermCons t) a = Foo Int



-- type Term (l :: Layout) = Term.TagToCons (Base l) l


-- read @Term :: IR Draft -> IR.Term Draft
-- read @Type :: IR Draft -> IR.Link Draft -- autofollow?


-- class Reader layer where
--     readIO :: forall layout. IR layout -> IO (Layer.View SubLayout layer)

--
-- foo = do
--     let x :: Term Acc
--         x = undefined
--         y = x
--         y :: Int
--     pure ()

-- data IR a = IR
--     { __tp   :: !(Link.Type )
--     , __term ::
--     }

-- data family TermX (t :: *) (a :: Layout)
--
-- data instance TermX Acc a = Term.TagToConsAcc
--     { __base :: !(Link.Term Acc a)
--     , __name :: !(Link.Name Acc a)
--     } deriving (Show, Eq)


-- data Foo a = Foo {-# UNPACK #-} !(TermX a)
--
-- data Term a
--     = Var !Int
--     | Acc !(IRLinkRef a) !(IRLinkRef a)
--     deriving (Generic, Show, Eq)
--
--
            -- read :: IRRef Draft -> IR Draft
            -- term :: IR Draft -> Term Draft
            -- tp   :: IR Draft -> Link.Type Draft Draft
            --
            -- readLayer @Type :: IRRef Draft -> Layer Type -- read only needed bits!
            --
            --
            -- read :: IRRef Var -> IR Var
            -- term :: IR Var -> Term Var
            -- tp   :: IR Var -> Link.Type Var Draft
            --
            -- jezeli odczytywanie bitow w czunkach jest tak szamo szybkie to moze zmergowac
            -- IRRef i IR ?
            -- po prostu
            -- read @Term zwracaloby tak samo dane jak
            -- read @Type ?
            --
            -- pattern amtche mozna tez tak :
            --
            -- case x of
            --     (Var, v) ->
            --     (Acc, a) ->
            --
            -- ale to nie jest ladne, bo nie pozwala na proste pattern matche pol

-- n <- read nref


-- -- -- === Instances === --
--
-- chunkSize :: Int
-- chunkSize = sizeOf' @Int
--
-- instance Storable a => Storable (Core a) where
--     sizeOf    _ = 3 * chunkSize ; {-# INLINE sizeOf    #-}
--     alignment _ = chunkSize     ; {-# INLINE alignment #-}
--     peek ptr = peek (intPtr ptr) >>= \case
--         0 -> UVar <$> peekByteOff ptr chunkSize
--         1 -> UAcc <$> peekByteOff ptr chunkSize
--         _ -> error "Unrecognized constructor"
--     {-# INLINE peek #-}
--     poke ptr = \case
--         UVar !a -> poke (intPtr ptr) 0 >> pokeByteOff ptr chunkSize a
--         UAcc !a -> poke (intPtr ptr) 1 >> pokeByteOff ptr chunkSize a
--     {-# INLINE poke #-}
--
-- instance Storable a => Storable (Acc a) where
--     sizeOf    _ = 2 * chunkSize ; {-# INLINE sizeOf    #-}
--     alignment _ = chunkSize     ; {-# INLINE alignment #-}
--     peek ptr = Acc <$> peek (castPtr ptr) <*> peekByteOff ptr chunkSize ; {-# INLINE peek #-}
--     poke ptr = \(Acc !b !n) -> poke (castPtr ptr) b >> pokeByteOff ptr chunkSize n ; {-# INLINE poke #-}
--
-- instance Storable a => Storable (Var a) where
--     sizeOf    _ = chunkSize ; {-# INLINE sizeOf    #-}
--     alignment _ = chunkSize ; {-# INLINE alignment #-}
--     peek ptr = Var <$> peek (castPtr ptr)        ; {-# INLINE peek #-}
--     poke ptr = \(Var !n) -> poke (castPtr ptr) n ; {-# INLINE poke #-}
--
--
--
--





-- x :: IRRef Draft
--
-- read n >>= \case
--     Var n ->
--
-- TermDraft
--
--
--
-- instance Storable a => Storable (Edge a) where
--     sizeOf    _ = 3 * chunkSize ; {-# INLINE sizeOf    #-}
--     alignment _ = chunkSize     ; {-# INLINE alignment #-}
--     peek ptr = peek (intPtr ptr) >>= \case
--         0 -> UVar <$> peekByteOff ptr chunkSize
--         1 -> UAcc <$> peekByteOff ptr chunkSize
--         _ -> error "Unrecognized constructor"
--     {-# INLINE peek #-}
--     poke ptr = \case
--         UVar !a -> poke (intPtr ptr) 0 >> pokeByteOff ptr chunkSize a
--         UAcc !a -> poke (intPtr ptr) 1 >> pokeByteOff ptr chunkSize a
--     {-# INLINE poke #-}



--
--
--
-- -- ---------------------------
-- -- -- === Testing utils === --
-- -- ---------------------------
-- --
-- -- mkSampleData :: Int -> Int -> Core ()
-- -- mkSampleData i j = UAcc $ Acc (Edge (EdgeID i)) (Edge (EdgeID j))
-- --
-- -- fromSampleData :: Core () -> Int
-- -- fromSampleData (UAcc (Acc (Edge (EdgeID i)) _)) = i
-- --
-- --
-- --
-- -- newtype Spec a = Spec a deriving (Show, Functor, Foldable, Traversable)
-- -- makeLenses ''Spec
-- --
-- --
-- -- instance Storable a => Storable (Spec a) where
-- --     sizeOf    _ = sizeOf' @a + 1                   ; {-# INLINE sizeOf    #-}
-- --     alignment _ = alignment' @a                    ; {-# INLINE alignment #-}
-- --     peek      p = coerce <$> peek @a (castPtr p)   ; {-# INLINE peek      #-}
-- --     poke      p a = poke @a (castPtr p) (coerce a) ; {-# INLINE poke      #-}
--
--
-- -- -------------------------
-- -- -- === Strict List === --
-- -- -------------------------
-- -- -- NOTE[piotrMocz]: Could alternatively use Data.List.Strict
-- --
-- -- data List = Cons {-# UNPACK #-} !Int List | Null deriving (Show) -- TODO: Why making strict spine makes it so slow to generate? With lazy one, even if we use all the elements, the whole process is shorter than generating it with strict spine.
-- --
-- -- instance Mempty    List where mempty = Null ; {-# INLINE mempty  #-}
-- -- instance Semigroup List where
-- --     l <> r = case l of
-- --         Null     -> r
-- --         Cons a t -> Cons a (t <> r)
-- --     {-# INLINE (<>) #-}
-- --
-- -- instance IsList List where
-- --     type Item List = Int
-- --     toList   = \case
-- --         Null      -> []
-- --         Cons a as -> a : toList as
-- --     fromList x = case x of
-- --         (a:as) -> Cons a $ fromList as
-- --         []     -> Null
-- --     {-# INLINE toList   #-}
-- --     {-# INLINE fromList #-}




--
--
-- data IRTYPE
-- data IRType a
--
-- data LITERAL
-- data VALUE
-- data THUNK
-- data PHRASE
-- data DRAFT
--
-- type Literal = IRType LITERAL
-- type Value   = IRType VALUE
-- type Thunk   = IRType THUNK
-- type Phrase  = IRType PHRASE
-- type Draft   = IRType DRAFT
--
-- data Format
--    = Literal
--    | Value
--    | Thunk
--    | Phrase
--    | Draft
--
--
-- -- data family IR (t :: Format)