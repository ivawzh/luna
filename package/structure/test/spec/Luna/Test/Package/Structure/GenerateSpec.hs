module Luna.Test.Package.Structure.GenerateSpec where

import Prologue

import qualified System.Directory            as Directory
import qualified System.IO.Temp              as Temp
import qualified Luna.Package.Structure.Name as Name

import Luna.Package.Structure.Generate ( genPackageStructure
                                       , isValidPkgName )
import System.FilePath                 ( FilePath, (</>) )
import Test.Hspec                      ( Spec, Expectation, it, describe
                                       , shouldBe )

--------------------------------------
-- === Testing Helper Functions === --
--------------------------------------

testPkgDir :: (FilePath -> Expectation) -> Expectation
testPkgDir = Temp.withSystemTempDirectory "pkgTest"

doesExist :: FilePath -> FilePath -> Expectation
doesExist path tempDir = do
    canonicalPath <- Directory.canonicalizePath tempDir
    let packageDir = canonicalPath </> "TestPackage"
    _ <- genPackageStructure packageDir

    dirExists <- Directory.doesPathExist (packageDir </> path)

    dirExists `shouldBe` True

findPackageDir :: Bool -> FilePath -> FilePath -> Expectation
findPackageDir shouldFind name rootPath = do
    canonicalPath <- Directory.canonicalizePath rootPath
    result <- genPackageStructure (canonicalPath </> name)

    case result of
        Right path -> do
            test <- Directory.doesDirectoryExist path
            test `shouldBe` shouldFind
        Left _ -> shouldFind `shouldBe` False

testNesting :: Bool -> FilePath -> Expectation
testNesting isNested tempPath = do
    canonicalPath <- Directory.canonicalizePath tempPath

    when isNested (Directory.createDirectory $ canonicalPath </> Name.configDir)
    result <- genPackageStructure (canonicalPath </> "TestPackage")
    case result of
        Left _ -> isNested `shouldBe` True
        Right _ -> isNested `shouldBe` False



-----------------------
-- === The Tests === --
-----------------------

spec :: Spec
spec = do
    describe "Generates the package directory with the correct name" $ do
        it "Creates the dir if the name is correct" . testPkgDir
            $ findPackageDir True "Foo"
        it "Rejects incorrect names" . testPkgDir $ findPackageDir False "bar"

    describe "Correct generation of top-level package components" $ do
        it "Creates the configuration directory" . testPkgDir
            $ doesExist ".luna-project"
        it "Creates the distribution directory" . testPkgDir
            $ doesExist "dist"
        it "Creates the source directory" . testPkgDir $ doesExist "src"
        it "Creates the test directory"   . testPkgDir $ doesExist "test"
        it "Creates the license"    . testPkgDir $ doesExist "LICENSE"
        it "Creates the readme"     . testPkgDir $ doesExist "README.md"
        it "Creates the .gitignore" . testPkgDir $ doesExist ".gitignore"

    describe "Correct generation of configuration files" $ do
        it "Creates config.yaml" . testPkgDir
            $ doesExist ".luna-project/config.yaml"
        it "Creates deps.yaml" . testPkgDir
            $ doesExist ".luna-project/deps.yaml"
        it "Creates deps-history.yaml" . testPkgDir
            $ doesExist ".luna-project/deps-history.yaml"

    describe "Correct generation of stub files" $ do
        it "Generates the project main" . testPkgDir
            $ doesExist "src/Main.luna"
        it "Generates the test main" . testPkgDir
            $ doesExist "test/Main.luna"

    describe "Generation of the LIR cache" .
        it "Generates the LIR cache directory" . testPkgDir
            $ doesExist "dist/.lir"

    describe "Package name checking" $ do
        it "Is a valid package name" $ isValidPkgName "Foo"
        it "Is an invalid packageName" . not $ isValidPkgName "baAr"

    describe "Detection of nested packages" $ do
        it "Is inside a package" . testPkgDir $ testNesting True
        it "Is not inside a package" . testPkgDir $ testNesting False
