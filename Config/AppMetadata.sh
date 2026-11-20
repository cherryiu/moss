#!/bin/zsh

# Single source of truth for both development and release app bundles.
# Values may be overridden by exporting the matching environment variable.
: "${MOSS_BUNDLE_IDENTIFIER:=com.todo-friend.moss}"
: "${MOSS_DISPLAY_NAME:=Moss}"
: "${MOSS_MARKETING_VERSION:=0.1.0}"
: "${MOSS_BUILD_NUMBER:=1}"
: "${MOSS_COPYRIGHT_OWNER:=Cherryiu}"

export MOSS_BUNDLE_IDENTIFIER
export MOSS_DISPLAY_NAME
export MOSS_MARKETING_VERSION
export MOSS_BUILD_NUMBER
export MOSS_COPYRIGHT_OWNER
