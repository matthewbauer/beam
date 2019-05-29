-- | Convenience methods for constructing backend-agnostic applications

module Database.Beam.Backend.URI where

import           Database.Beam.Backend.SQL

import           Control.Exception

import qualified Data.Map as M

import           Network.URI

data BeamResourceNotFound = BeamResourceNotFound deriving Show
instance Exception BeamResourceNotFound

data BeamOpenURIInvalid = BeamOpenURIInvalid deriving Show
instance Exception BeamOpenURIInvalid

data BeamOpenURIUnsupportedScheme = BeamOpenURIUnsupportedScheme String deriving Show
instance Exception BeamOpenURIUnsupportedScheme

data BeamURIOpener c where
  BeamURIOpener :: MonadBeam syntax be hdl m
                => c syntax be hdl m
                -> (forall a. URI -> (hdl -> IO a) -> IO a)
                -> BeamURIOpener c
newtype BeamURIOpeners c where
  BeamURIOpeners :: M.Map String (BeamURIOpener c) -> BeamURIOpeners c

instance Semigroup (BeamURIOpeners c) where
  (BeamURIOpeners a) <> (BeamURIOpeners b) =
    BeamURIOpeners (a <> b)

instance Monoid (BeamURIOpeners c) where
  mempty = BeamURIOpeners mempty

mkUriOpener :: MonadBeam syntax be hdl m
            => String -> (forall a. URI -> (hdl -> IO a) -> IO a)
            -> c syntax be hdl m
            -> BeamURIOpeners c
mkUriOpener schemeNm opener c = BeamURIOpeners (M.singleton schemeNm (BeamURIOpener c opener))

withDbFromUri :: forall c a
               . BeamURIOpeners c
              -> String
              -> (forall syntax be hdl m. MonadBeam syntax be hdl m => c syntax be hdl m -> m a)
              -> IO a
withDbFromUri protos uri actionWithDb =
  withDbConnection protos uri (\c hdl -> withDatabase hdl (actionWithDb c))

withDbConnection :: forall c a
                  . BeamURIOpeners c
                 -> String
                 -> (forall syntax be hdl m. MonadBeam syntax be hdl m =>
                      c syntax be hdl m -> hdl -> IO a)
                 -> IO a
withDbConnection (BeamURIOpeners protos) uri actionWithDb =
  case parseURI uri of
    Nothing -> throwIO BeamOpenURIInvalid
    Just parsedUri ->
      case M.lookup (uriScheme parsedUri) protos of
        Nothing -> throwIO (BeamOpenURIUnsupportedScheme (uriScheme parsedUri))
        Just (BeamURIOpener c withURI) ->
          withURI parsedUri (actionWithDb c)
