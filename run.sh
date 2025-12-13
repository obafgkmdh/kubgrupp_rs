#!/bin/sh

make -j8 && cargo run -- --scene-file $1
