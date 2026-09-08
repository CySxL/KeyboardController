#/bin/sh

#	build for regular jailbreaks
make clean
make package FINALPACKAGE=1

#	build for rootless jailbreaks
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

#	build for roothide jailbreaks
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
