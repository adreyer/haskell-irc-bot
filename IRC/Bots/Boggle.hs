-- Copyright 2010 Rev. Johnny Healey
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

module IRC.Bots.Boggle (boggle, initialBoggle, initialRandomBoggle) where

import IRC
import IRC.Bot
import Text.Regex.PCRE.Light.Char8
import Data.Array
import qualified Data.Map as Map
import qualified Data.Set as Set
import Random
import IRC.Bots.Boggle.Board
import IRC.Bots.Boggle.Solver
import Maybe
import Data.Char
import Data.List

type Scores = Map.Map String Int
type WordSet = Set.Set String

data Game = Countdown | Game Board Integer Scores WordSet
data BoggleBot = BoggleBot Dictionary (Maybe Game) StdGen Int

getDictionary = do
    (BoggleBot dict _ _ _) <- get
    return dict

getGame = do
    (BoggleBot _ game _ _) <- get
    return game

putGame game = do
    (BoggleBot dict _ gen sb) <- get
    put (BoggleBot dict game gen sb)

getGen = do
    (BoggleBot _ _ gen _) <- get
    return gen

putGen gen = do
    (BoggleBot dict game _ sb) <- get
    put (BoggleBot dict game gen sb)

getScrollback = do
    (BoggleBot _ _ _ sb) <- get
    return sb

putScrollback sb = do
    (BoggleBot dict game gen _) <- get
    put (BoggleBot dict game gen sb)

incrementScrollback = do
    sb <- getScrollback
    let sb' = sb + 1
    putScrollback sb'
    return sb'

makeRandomBoard :: OutputEvent BoggleBot Board
makeRandomBoard = do
    gen <- getGen
    let (board, gen') = makeBoard gen
    putGen gen'
    return board

formatLetter l = 
    if length l == 1
        then l ++ "  "
        else l ++ " "

outputBoard :: Board -> OutputEvent BoggleBot ()
outputBoard b = do
    mapM privMsg [concatMap formatLetter r | r <- rows b]
    putScrollback 0
    return ()

initialBoggle dict init = BoggleBot dict Nothing (mkStdGen init) 0

formatScore (name,score) = name ++ " : " ++ (show score)

finishGame = do
    privMsg "Time is up!"
    game <- getGame
    let (Game _ _ scores _) = fromJust $ game
        scores' = sortBy (\(_,s1) -> \(_,s2) -> compare s2 s1) $ 
            Map.toList scores
    mapM privMsg $ map formatScore scores'
    putGame Nothing

validWords solutions text = 
    let re = compile "[a-z]{3,}" [caseless]
    in catMaybes $ do
        word <- words text
        return $ do
            possible <- match re word []
            let first = map toUpper $ head possible
            if Set.member first solutions
                then return first
                else Nothing

wordValue w = 
    let score = (length w) - 3
        fibs = 1:1:zipWith (+) fibs (tail fibs)
    in if score >= 0
        then fibs !! score
        else 0

alterScore new current = 
    case current of
        Nothing -> Just new
        Just val -> Just $ new + val

score user word = do
    game <- getGame
    let (Game board start scores words) = fromJust game
        value = wordValue word
        scores' = Map.alter (alterScore value) user scores
        words' = Set.delete word words
    putGame $ Just (Game board start scores' words')

play :: Bot BoggleBot
play (PrivMsg user _ text) _ = do
    game <- getGame
    case game of
        Nothing -> return ()
        Just Countdown -> return ()
        Just (Game board _ _ solutions) ->
            let words = validWords solutions text
            in do
                mapM (score user) words
                sb <- incrementScrollback
                if sb > 20
                    then outputBoard board
                    else return ()
play _ _ = return ()

countdown :: Integer -> OutputEvent BoggleBot () -> OutputEvent BoggleBot ()
countdown ts action = 
    let countMsg 9 = privMsg "1 second until Boggle Time"
        countMsg x = (privMsg $ (show $ 10 - x) ++ 
            " seconds until Boggle Time!")
        remaining ts x = delayEvent (ts + x) $ countMsg x
    in do
        putGame $ Just Countdown
        mapM (remaining ts) [0..9]
        delayEvent (ts + 10) action

startPlaying :: Integer -> OutputEvent BoggleBot ()
startPlaying ts = do
    board <- makeRandomBoard
    dict <- getDictionary
    let words = solve dict board
    putGame $ Just (Game board ts Map.empty words)
    outputBoard board
    delayEvent (ts + 60) $ do
        privMsg "Two Minutes Remaining"
        outputBoard board
    delayEvent (ts + 120) $ do
        privMsg "One Minute Remaining"
        outputBoard board
    delayEvent (ts + 170) $ do
        privMsg "Ten Seconds Remaining"
        outputBoard board
    delayEvent (ts + 180) finishGame

startGame :: Bot BoggleBot
startGame msg ts = 
    let re = compile "boggle time!" [caseless]
    in case privMsgTextMatch re [] msg of
        Just _ -> do
            countdown ts (startPlaying $ ts + 10)
        Nothing -> return ()

boggle :: Bot BoggleBot
boggle msg ts = do
    game <- getGame
    case game of
        Just _ -> play msg ts
        Nothing -> startGame msg ts

initialRandomBoggle dict = do
    rand <- randomIO
    return $ initialBoggle dict rand
