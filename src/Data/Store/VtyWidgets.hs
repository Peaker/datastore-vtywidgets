{-# OPTIONS -O2 -Wall #-}

module Data.Store.VtyWidgets
    (MWidget, TWidget,
     appendBoxChild, popCurChild,
     makeBox, makeTextEdit, makeLineEdit, makeCompletion, makeSimpleCompletion, makeChoiceWidget,
     widgetDownTransaction)
where

import           Control.Monad                     (when, liftM)
import           Data.Function.Utils               (result)
import qualified Graphics.UI.VtyWidgets.Box        as Box
import qualified Graphics.UI.VtyWidgets.TextEdit   as TextEdit
import qualified Graphics.UI.VtyWidgets.Completion as Completion
import           Graphics.UI.VtyWidgets.Widget     (Widget)
import qualified Data.Store.Property               as Property
import qualified Data.Store.Transaction            as Transaction
import           Data.Store.Transaction            (Transaction, Store)
import           Data.Maybe                        (listToMaybe)

removeAt :: Int -> [a] -> [a]
removeAt n xs = take n xs ++ drop (n+1) xs

safeIndex :: Integral ix => ix -> [a] -> Maybe a
safeIndex n = listToMaybe . drop (fromIntegral n)

type MWidget m = m (Widget (m ()))
type TWidget t m a = Widget (Transaction t m a)

appendBoxChild :: Monad m =>
                   Transaction.Property t m Box.Model ->
                   Transaction.Property t m [a] ->
                   a -> Transaction t m ()
appendBoxChild boxModelRef valuesRef value = do
  values <- Property.get valuesRef
  Property.set valuesRef (values ++ [value])
  Property.set boxModelRef . Box.Model . length $ values

popCurChild :: Monad m =>
               Transaction.Property t m Box.Model ->
               Transaction.Property t m [a] ->
               Transaction t m (Maybe a)
popCurChild boxModelRef valuesRef = do
  values <- Property.get valuesRef
  curIndex <- Box.modelCursor `liftM` Property.get boxModelRef
  let value = curIndex `safeIndex` values
  maybe (return ()) (delChild curIndex values) value
  return value
  where
    delChild curIndex values _child = do
      Property.set valuesRef (curIndex `removeAt` values)
      when (curIndex >= length values - 1) .
        Property.pureModify boxModelRef . Box.inModel $ subtract 1

makeBox :: Monad m =>
           Box.Orientation ->
           [TWidget t m ()] ->
           Transaction.Property t m Box.Model ->
           MWidget (Transaction t m)
makeBox orientation rows boxModelRef =
  Box.make orientation (Property.set boxModelRef) rows `liftM`
  Property.get boxModelRef

makeWidget :: Monad m =>
              (model -> Widget model) ->
              Transaction.Property t m model ->
              MWidget (Transaction t m)
makeWidget w ref = (fmap (Property.set ref) . w) `liftM`
                   Property.get ref

makeTextEdit :: Monad m => TextEdit.Theme -> String -> Int ->
                Transaction.Property t m TextEdit.Model ->
                MWidget (Transaction t m)
makeTextEdit =
  (result . result . result) makeWidget TextEdit.make

makeLineEdit :: Monad m => TextEdit.Theme -> String ->
                Transaction.Property t m TextEdit.Model ->
                MWidget (Transaction t m)
makeLineEdit =
  (result . result) makeWidget TextEdit.lineEdit

makeCompletion :: Monad m =>
                  Completion.Theme ->
                  [(String, Int)] -> Int -> String -> Int ->
                  Transaction.Property t m Completion.Model ->
                  MWidget (Transaction t m)
makeCompletion =
  (result . result . result .
   result . result) makeWidget Completion.make

makeSimpleCompletion :: Monad m =>
                        Completion.Theme ->
                        [String] -> Int -> String -> Int ->
                        Transaction.Property t m Completion.Model ->
                        MWidget (Transaction t m)
makeSimpleCompletion =
  (result . result . result .
   result . result) makeWidget Completion.makeSimple

makeChoiceWidget :: Monad m =>
                    Box.Orientation ->
                    [(TWidget t m (), k)] ->
                    Transaction.Property t m Box.Model ->
                    Transaction t m (TWidget t m (), k)
makeChoiceWidget orientation keys boxModelRef = do
  widget <- makeBox orientation widgets boxModelRef
  itemIndex <- Box.modelCursor `liftM` Property.get boxModelRef
  return (widget, items !! min maxIndex itemIndex)
  where
    maxIndex = length items - 1
    widgets = map fst keys
    items = map snd keys


-- Take a widget parameterized on transaction on views (that lives in
-- a nested transaction monad) and convert it to one parameterized on
-- the nested transaction
widgetDownTransaction :: Monad m =>
                         Store t m ->
                         MWidget (Transaction t m) ->
                         MWidget m
widgetDownTransaction store = runTrans . (liftM . fmap) runTrans
  where
    runTrans = Transaction.run store
