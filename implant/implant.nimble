# Package information
# Nimhawk isn't really a package, Nimble is mainly used for easy dependency management
version       = "1.4.0"
author        = "hdbreaker"
description   = "A Powerful, modular, lightweight and efficient implant heavily based on @chvancooten NimPlant project."
license       = "MIT"
srcDir        = "."
skipDirs      = @["bin", "commands", "util"]

requires "nim >= 1.6.10"
requires "nimcrypto >= 0.6.0"
requires "parsetoml >= 0.7.1"
requires "pixie >= 5.0.6"
requires "ptr_math >= 0.3.0"
requires "puppy >= 2.1.0"
requires "winim >= 3.9.2"
requires "zippy >= 0.10.4"
requires "nimvoke >= 0.1.0"

task install, "Install task to allow nimble install to run":
  echo "Installing dependencies only."