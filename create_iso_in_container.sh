#!/bin/bash

./bootstrap.sh clean
./bootstrap.sh step isomount
./bootstrap.sh step createtemplate
./bootstrap.sh step scandeps
./bootstrap.sh step createrepo
./bootstrap.sh step createiso
./bootstrap.sh step isounmount
cp ./Rocky-8.3.2011-x86_64-minimal.iso /mnt/
