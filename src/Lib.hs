{-# LANGUAGE BangPatterns    #-}
{-# LANGUAGE TemplateHaskell #-}
module Lib where


import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node                     (initRemoteTable)
import Control.Monad
import Network.Transport.TCP                                (createTransport,defaultTCPParameters)
import Prelude hiding (plog)

import Control.Monad.State

import Utils

import System.IO.Unsafe

type WorkQueue = ProcessId
type Master = ProcessId

doWork :: String -> IO String
doWork = runArgon

worker :: (Master, WorkQueue) -> Process ()
worker (manager, workQueue) = do
  me <- getSelfPid
  plog " Ready to work! " 
  run me
  where
    run :: ProcessId -> Process ()
    run me = do
      send workQueue me
      receiveWait[match work, match end]
      where
        work f = do
          plog $ " Working on: " ++ show f
          work <- liftIO $ doWork f
          send manager work
          plog " Finished work :) "
          run me 
        end () = do
          plog " Terminating worker "
          return ()

remotable['worker] 

rtable :: RemoteTable
rtable = Lib.__remoteTable initRemoteTable

manager :: Files -> [NodeId] -> Process String
manager files workers = do
  me <- getSelfPid
  workQueue <- spawnLocal $ do 
    forM_ files $ \f -> do
      id <- expect
      send id f
    forever $ do
      id <- expect
      send id ()
  forM_ workers $ \ nid -> spawn nid $ $(mkClosure 'worker) (me,workQueue)
  getResults $ length files

getResults :: Int -> Process String
getResults = run ""
  where
    run :: String -> Int -> Process String
    run r 0 = return r
    run r n = do
      s <- expect
      run (r ++ s) (n - 1)
      

