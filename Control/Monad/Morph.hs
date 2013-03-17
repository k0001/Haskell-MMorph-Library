{-| A monad morphism is a natural transformation:

> morph :: forall a . m a -> n a

    ... that obeys the following two laws:

> morph $ do x <- m  =  do x <- morph m
>            f x           morph (f x)
>
> morph (return x) = return x

    ... which are equivalent to the following two functor laws:

> morph . (f >=> g) = morph . f >=> morph . g
>
> morph . return = return

    Examples of monad morphisms include:

    * 'lift' (from 'MonadTrans')

    * 'squash' (See below)

    * @'hoist' f@ (See below), if @f@ is a monad morphism

    * @(f . g)@, if @f@ and @g@ are both monad morphisms

    * 'id'

    Monad morphisms commonly arise when manipulating existing monad transformer
    code for compatibility purposes.  The 'MFunctor', 'MonadTrans', and
    'MMonad' classes define standard ways to change monad transformer stacks:

    * 'lift' introduces a new monad transformer layer of any type.

    * 'squash' flattens two identical monad transformer layers into a single
      layer of the same type.

    * 'hoist' maps monad morphisms to modify deeper layers of the monad
       transformer stack.

-}

{-# LANGUAGE Rank2Types #-}

module Control.Monad.Morph (
    -- * Functors over Monads
    MFunctor(..),
    -- * Monads over Monads
    MMonad(..),
    MonadTrans(lift),
    squash,
    (>|>),
    (<|<),
    (=<|),
    (|>=)

    -- * Tutorial
    -- $tutorial

    -- ** Generalizing base monads
    -- $generalize

    -- ** Monad morphisms
    -- $mmorph

    -- ** Interleaving transformers
    -- $interleave

    -- ** Embedding transformers
    -- $embed
    ) where

import Control.Monad.Trans.Class (MonadTrans(lift))
import qualified Control.Monad.Trans.Error         as E
import qualified Control.Monad.Trans.Identity      as I
import qualified Control.Monad.Trans.Maybe         as M
import qualified Control.Monad.Trans.Reader        as R
import qualified Control.Monad.Trans.RWS.Lazy      as RWS
import qualified Control.Monad.Trans.RWS.Strict    as RWS'
import qualified Control.Monad.Trans.State.Lazy    as S
import qualified Control.Monad.Trans.State.Strict  as S'
import qualified Control.Monad.Trans.Writer.Lazy   as W'
import qualified Control.Monad.Trans.Writer.Strict as W
import Data.Monoid (Monoid, mappend)

-- For documentation
import Control.Exception (try)
import Control.Monad ((=<<), (>=>), (<=<), join)
import Data.Functor.Identity (Identity)

{-| A functor in the category of monads, using 'hoist' as the analog of 'fmap':

> hoist (f . g) = hoist f . hoist g
>
> hoist id = id
-}
class MFunctor t where
    {-| Lift a monad morphism from @m@ to @n@ into a monad morphism from
        @(t m)@ to @(t n)@
    -}
    hoist :: (Monad m) => (forall a . m a -> n a) -> t m b -> t n b

instance MFunctor (E.ErrorT e) where
    hoist nat m = E.ErrorT (nat (E.runErrorT m))

instance MFunctor I.IdentityT where
    hoist nat m = I.IdentityT (nat (I.runIdentityT m))

instance MFunctor M.MaybeT where
    hoist nat m = M.MaybeT (nat (M.runMaybeT m))

instance MFunctor (R.ReaderT r) where
    hoist nat m = R.ReaderT (\i -> nat (R.runReaderT m i))

instance MFunctor (RWS.RWST r w s) where
    hoist nat m = RWS.RWST (\r s -> nat (RWS.runRWST m r s))

instance MFunctor (RWS'.RWST r w s) where
    hoist nat m = RWS'.RWST (\r s -> nat (RWS'.runRWST m r s))

instance MFunctor (S.StateT s) where
    hoist nat m = S.StateT (\s -> nat (S.runStateT m s))

instance MFunctor (S'.StateT s) where
    hoist nat m = S'.StateT (\s -> nat (S'.runStateT m s))

instance MFunctor (W.WriterT w) where
    hoist nat m = W.WriterT (nat (W.runWriterT m))

instance MFunctor (W'.WriterT w) where
    hoist nat m = W'.WriterT (nat (W'.runWriterT m))

{-| A monad in the category of monads, using 'lift' from 'MonadTrans' as the
    analog of 'return' and 'embed' as the analog of ('=<<'):

> embed lift = id
>
> embed f (lift m) = f m
>
> embed g (embed f t) = embed (\m -> embed g (f m)) t
-}
class (MFunctor t, MonadTrans t) => MMonad t where
    {-| Embed a newly created 'MMonad' layer within an existing layer

        'embed' is analogous to ('=<<')
    -}
    embed :: (Monad n) => (forall a . m a -> t n a) -> t m b -> t n b

{-| Squash two 'MMonad' layers into a single layer

    'squash' is analogous to 'join'
-}
squash :: (Monad m, MMonad t) => t (t m) a -> t m a
squash = embed id

infixr 2 >|>, =<|
infixl 2 <|<, |>=

{-| Compose two 'MMonad' layer-building functions

    ('>|>') is analogous to ('>=>')
-}
(>|>)
    :: (Monad m3, MMonad t)
    => (forall a . m1 a -> t m2 a)
    -> (forall b . m2 b -> t m3 b)
    ->             m1 c -> t m3 c
(f >|> g) m = embed g (f m)

{-| Equivalent to ('>|>') with the arguments flipped

    ('<|<') is analogous to ('<=<')
-}
(<|<)
    :: (Monad m3, MMonad t)
    => (forall b . m2 b -> t m3 b)
    -> (forall a . m1 a -> t m2 a)
    ->             m1 c -> t m3 c
(g <|< f) m = embed g (f m)

{-| An infix operator equivalent to 'embed'

    ('=<|') is analogous to ('=<<')
-}
(=<|) :: (Monad n, MMonad t) => (forall a . m a -> t n a) -> t m b -> t n b
(=<|) = embed

{-| Equivalent to ('=<|') with the arguments flipped

    ('|>=') is analogous to ('>>=')
-}
(|>=) :: (Monad n, MMonad t) => t m b -> (forall a . m a -> t n a) -> t n b
t |>= f = embed f t

instance (E.Error e) => MMonad (E.ErrorT e) where
    embed f m = E.ErrorT (do
        x <- E.runErrorT (f (E.runErrorT m))
        return (case x of
            Left         e  -> Left e
            Right (Left  e) -> Left e
            Right (Right a) -> Right a ) )

instance MMonad I.IdentityT where
    embed f m = f (I.runIdentityT m)

instance MMonad M.MaybeT where
    embed f m = M.MaybeT (do
        x <- M.runMaybeT (f (M.runMaybeT m))
        return (case x of
            Nothing       -> Nothing
            Just Nothing  -> Nothing
            Just (Just a) -> Just a ) )

instance MMonad (R.ReaderT r) where
    embed f m = R.ReaderT (\i -> R.runReaderT (f (R.runReaderT m i)) i)

instance (Monoid w) => MMonad (W.WriterT w) where
    embed f m = W.WriterT (do
        ~((a, w1), w2) <- W.runWriterT (f (W.runWriterT m))
        return (a, mappend w1 w2) )

instance (Monoid w) => MMonad (W'.WriterT w) where
    embed f m = W'.WriterT (do
        ((a, w1), w2) <- W'.runWriterT (f (W'.runWriterT m))
        return (a, mappend w1 w2) )

{- $tutorial
    Monadic code written using a particular monad transformer stack does not
    compose with monadic code using a different stack.
    A monad morphism is a natural transformation between monads that can be
    used to introduce new transforming layers to already existing monadic code
    without changing its original form. Thus, it becomes possible to introduce
    as many transforming layers as needed to recreate a transformer stack that
    could be composed.

    The following examples illustrate how to use monad morphisms for such
    purposes.
-}

{- $generalize
    Imagine that some library provided the following 'S.State' code:

> import Control.Monad.Trans.State
>
> tick :: State Int ()
> tick = modify (+1)

    ... but we would prefer to reuse @tick@ within a larger
    @('S.StateT' Int 'IO')@ block in order to mix in 'IO' actions.

    We could patch the original library to generalize @tick@'s type signature:

> tick :: (Monad m) => StateT Int m ()

    ... but we would prefer to not modify @tick@, if possible. How can
    we generalize @tick@'s type without modifying the original code?

    We can solve this if we realize that 'S.State' is a type synonym for
    'S.StateT' with an 'Identity' base monad:

> type State s = StateT s Identity

    ... which means that @tick@'s true type is actually:

> tick :: StateT Int Identity ()

    Now all we need is a function that @generalize@s the 'Identity' base monad
    to be any monad:

> import Data.Functor.Identity
>
> generalize :: (Monad m) => Identity a -> m a
> generalize m = return (runIdentity m)

    ... which we can 'hoist' to change @tick@'s base monad:

> hoist :: (Monad m, MFunctor t) => (forall a . m a -> n a) -> t m b -> t n b
>
> hoist generalize :: (Monad m, MFunctor t) => t Identity b -> t m b
>
> hoist generalize tick :: (Monad m) => StateT Int m ()

    This lets us mix @tick@ alongside any other monad, such as 'IO', by using
    'lift':

> import Control.Monad.Morph
> import Control.Monad.Trans.Class
>
> tock                        ::                   StateT Int IO ()
> tock = do
>     hoist generalize tick   :: (Monad      m) => StateT Int m  ()
>     lift $ putStrLn "Tock!" :: (MonadTrans t) => t          IO ()

>>> runStateT tock 0
Tock!
((), 1)

-}

{- $mmorph
    Notice that @generalize@ is a monad morphism, and satisfies the monad
    morphism laws.  The following two proofs serve as case studies for proving
    that something is a monad morphism:

> generalize (return x)
>
> -- Definition of 'return' for the Identity monad
> = generalize (Identity x)
>
> -- Definition of 'generalize'
> = return (runIdentity (Identity x))
>
> -- runIdentity (Identity x) = x
> = return x

> generalize $ do x <- m
>                 f x
>
> -- Definition of (>>=) for the Identity monad
> = generalize (f (runIdentity m))
>
> -- Definition of 'generalize'
> = return (runIdentity (f (runIdentity m)))
>
> -- Monad law: Left identity
> = do x <- return (runIdentity m)
>      return (runIdentity (f x))
>
> -- Definition of 'generalize' in reverse
> = do x <- generalize m
>      generalize (f x)
-}

{- $interleave
    You can combine 'hoist' and 'lift' to insert arbitrary layers anywhere
    within a monad transformer stack.  This comes in handy when interleaving two
    diverse stacks.

    For example, we might want to combine the following @save@ function:

> import Control.Monad.Trans.Writer
>
> -- i.e. :: StateT Int (WriterT [Int] Identity) ()
> save    :: StateT Int (Writer  [Int]) ()
> save = do
>     n <- get
>     lift $ tell [n]

    ... with our previous @tock@ function:

> tock :: StateT Int IO ()

    However, @save@ and @tock@ differ in two ways:

    * @tock@ lacks a 'W.WriterT' layer

    * @save@ has an 'Identity' base monad

    We can use 'hoist' to add enough layers to each of these two stacks so that
    they become compatible within a same 'program'. The following stack will
    be enough for our purposes:

> program :: StateT Int (WriterT [Int] IO) ()

    First we need to insert a 'W.WriterT' layer in @tock@. Since this new layer
    will be just below the current outermost layer ('S.StateT'), we use 'hoist'
    just once, together with the simplest monad morphism that would 'lift' a
    monadic action to an outer transformer layer:

> hoist lift tock :: (MonadTrans t) => StateT Int (t IO) ()

    Then we need to 'generalize' @save@'s base monad, but this time we need to
    'hoist' twice because we don't want to use our monad morphism on our outer
    transformer, but instead, on the one just below it:

>  hoist (hoist generalize) save :: (Monad m) => StateT Int (WriterT [Int] m ) ()

    Now the transformers stacks are compatible and can be composed. Here's our
    full program:

> import Control.Monad
>
> program ::                   StateT Int (WriterT [Int] IO) ()
> program = replicateM_ 4 $ do
>     hoist lift tock
>         :: (MonadTrans t) => StateT Int (t             IO) ()
>     hoist (hoist generalize) save
>         :: (Monad      m) => StateT Int (WriterT [Int] m ) ()

>>> execWriterT (runStateT program 0)
Tock!
Tock!
Tock!
Tock!
[1,2,3,4]

-}

{- $embed
    Suppose we decided to @check@ all 'IO' exceptions using a combination of
    'try' and 'ErrorT':

> import Control.Exception
> import Control.Monad.Trans.Class
> import Control.Monad.Trans.Error
>
> check :: IO a -> ErrorT IOException IO a
> check io = ErrorT (try io)

    ... but then we forget to use it in one spot, mistakenly using 'lift'
    instead of @check@:

> program :: ErrorT IOException IO ()
> program = do
>     str <- lift $ readFile "test.txt"
>     check $ putStr str

>>> runErrorT program
*** Exception: test.txt: openFile: does not exist (No such file or directory)

    How could we go back and fix 'program' without modifying its source code?

    Well, @check@ is a monad morphism, but we can't 'hoist' it to modify the
    base monad because then we get two 'E.ErrorT' layers instead of one:

> hoist check
>     :: ErrorT IOException IO a -> ErrorT IOException (ErrorT IOException IO) a

    Instead, we want to 'embed' all newly generated exceptions in the existing
    'E.ErrorT' layer:

> embed check :: ErrorT IOException IO a -> ErrorT IOException IO a

    This correctly checks the exceptions that slipped through the cracks:

>>> import Control.Monad.Morph
>>> runErrorT (embed check program)
Left test.txt: openFile: does not exist (No such file or directory)

-}
