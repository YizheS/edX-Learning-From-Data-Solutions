import Control.Applicative ((<$>), (<*>))
import Control.Monad (forM, forM_, replicateM)
import Control.Monad.Random (Rand, RandomGen, getRandom, runRand)
import qualified Data.Array as A
import qualified Data.Array.Unboxed as U
import Data.List (genericLength, transpose)
import Debug.Trace (traceShow)
import Learning.Perceptron
import Numeric.LinearAlgebra
import SVM
import System.Random (mkStdGen)
import Text.Printf (printf)

-- Exercises 1 - 5
getX :: Matrix Double -> Matrix Double
getX = takeColumns 2

getY :: Matrix Double -> Vector Double
getY = head . toColumns . dropColumns 2

nonLinear :: Matrix Double -> Matrix Double
nonLinear = fromRows . map (fromList . nonLinearRow . toList) . toRows
  where
    nonLinearRow [x1, x2] = [1, x1, x2, x1^2, x2^2, x1 * x2, abs (x1 - x2), abs (x1 + x2)]

classificationError :: Vector Double -> Vector Double -> Double
classificationError v y = let sv = mapVector signum v
                              diffs = zipVectorWith (((fromIntegral . fromEnum).) . (/=)) sv y
                          in  foldVector (+) 0 diffs / fromIntegral (dim y)

regression :: Matrix Double -> Vector Double -> Vector Double
regression x y = let xt = trans x
                     xtx = multiply xt x
                     z = multiply (pinv xtx) xt
                 in  z `mXv` y

experiment :: Matrix Double -> Vector Double -> Matrix Double -> Vector Double -> Double
experiment xtrain ytrain xval yval = let z = regression xtrain ytrain
                                     in  classificationError (xval `mXv` z) yval
-- Exercise 6
minimumEstimator :: RandomGen g => Rand g Double
minimumEstimator = min <$> getRandom <*> getRandom

minimumExperiments :: RandomGen g => Rand g Double
minimumExperiments = replicateM iterations minimumEstimator >>= average
  where
    iterations = 10000
    average xs = return $ sum xs / genericLength xs

-- Exercise 7
type Point = (Double, Double)
type RegressionModel = Point -> Point -> (Double -> Double)

loo :: [a] -> [(a, [a])]
loo [] = []
loo (x:xs) = loo' [] x xs
  where
    loo' xs y [] = [(y, xs)]
    loo' xs y (z:zs) = (y, xs ++ z:zs) : loo' (xs ++ [y]) z zs

constantModel :: RegressionModel
constantModel (_, py) (_, qy) = const a
  where
    a = (qy + py) / 2

linearModel :: RegressionModel
linearModel (px, py) (qx, qy) x = m * x + b
  where
    m = dy / dx
    dy = py - qy
    dx = px - qx
    b = py - m * px

squaredError :: (Double -> Double) -> Point -> Double
squaredError f (x, y) = (f x - y)^2

trainAndValidate :: [Point] -> RegressionModel -> Double
trainAndValidate ps m = average
  where
    trainLOO (a, [p, q]) = squaredError (m p q) a
    errors = map trainLOO (loo ps)
    average = sum errors / genericLength errors

-- Exercises 8 - 9

type ClassifiedPoint = ([Double], Bool)
perceptronSVMComparison :: [ClassifiedPoint] -> [ClassifiedPoint] -> [Double]
perceptronSVMComparison dataset testset = let pe = perceptronError dataset testset
                                              (se, nv) = svmError dataset testset
                                          in [pe, se, nv]

perceptronError :: [ClassifiedPoint] -> [ClassifiedPoint] -> Double
perceptronError dataset testset = let f = pla dataset
                                      fxs = map (f . fst) dataset
                                      ys = map snd testset
                                      errors = filter id $ zipWith (/=) fxs ys
                                  in  genericLength errors / genericLength testset

svmError :: [ClassifiedPoint] -> [ClassifiedPoint] -> (Double, Double)
svmError dataset testset = let n = length dataset
                               x = A.listArray (1, n) (map fst dataset)
                               labels = map (((-1)^) . (+1) . fromEnum . snd) dataset
                               y = U.listArray (1, n) labels
                               d = DataSet x y
                               svm = LSSVM (KernelFunction linearKernelFunction) 1 [0..]
                               SVMSolution alpha sv bias = solve svm d 1e-5 100000
                           in traceShow (alpha, sv) $ error "fooo"-- undefined

generatePoints :: RandomGen g => Int -> Rand g [ClassifiedPoint]
generatePoints k = do
  [px, py, qx, qy] <- replicateM 4 getRandom
  points <- replicateM k (replicateM 2 getRandom)
  let checker [x, y] = ((qx - px)*(y - py) - (qy - py)*(x - px)) > 0
      classifications = map checker points
  return $ zip points classifications

runComparison :: RandomGen g => Int -> Int -> Rand g [Double]
runComparison n runs = do
  results <- replicateM runs runOnce
  let averages = map ((/ fromIntegral runs) . sum) $ transpose results
  return averages
  where
    k = 10
    runOnce = do
      points <- generatePoints (n + k)
      let dataset = take n points
          testset = drop n points
      return $ perceptronSVMComparison dataset testset

main = do
  inputMatrix <- fromFile "in.dta" (35, 3)
  testMatrix <- fromFile "out.dta" (250, 3)

  let dx = nonLinear (getX inputMatrix)
      dy = getY inputMatrix
      xtest = nonLinear (getX testMatrix)
      ytest = getY testMatrix
      xtrain = takeRows 25 dx
      ytrain = subVector 0 25 dy
      xval = dropRows 25 dx
      yval = subVector 25 10 dy

  putStr "1 & 2)"
  firstTest <- forM [3..7] $ \k ->
    let trim = takeColumns (k + 1)
        run = experiment (trim xtrain) ytrain
        e_val = run (trim xval) yval
        e_test = run (trim xtest) ytest
        str = printf "\tk = %d: E_val = %.5f, E_out = %.5f" k e_val e_test
    in putStrLn str >> return (e_val, e_test)

  putStr "\n3 & 4)"
  secondTest <- forM [1..7] $ \k ->
    let trim = takeColumns (k + 1)
        run = experiment (trim xval) yval
        e_val = run (trim xtrain) ytrain
        e_test = run (trim xtest) ytest
        str = printf "\tk = %d: E_val = %.5f, E_out = %.5f" k e_val e_test
    in putStrLn str >> return (e_val, e_test)

  putStrLn $ printf "\n5)\t(%.5f, %.5f)" (snd $ minimum firstTest) (snd $ minimum secondTest)

  let g = mkStdGen 12345
  let (expectedMinimum, g') = runRand minimumExperiments g
  putStrLn $ printf "\n6)\t%.8f" expectedMinimum

  let ps = map sqrt [sqrt 3 + 4,
                     sqrt 3 - 1,
                     9 + 4 * sqrt 6,
                     9 - sqrt 6]
      fixed = [(-1, 0), (1, 0)]
  let triples = map (\p -> (p, 1):fixed) ps
  putStr "\n7)"
  forM_ (zip ['a'..'d'] triples) $ \(label, triple) ->
    let f = trainAndValidate triple
        ec = f constantModel
        el = f linearModel
    in putStrLn $ printf "\t%c) Constant: %.5f, Linear: %.5f" label ec el

  let (results, g'') = runRand (runComparison 10 10) g'
  print results
