#!/usr/bin/env bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# https://github.com/kbuckleys/
#
# The parts of this shell that are QML rather than plain JS, driven by Qt's
# own event synthesis. scripts/test.js covers the pure .js halves; this covers
# the ones where the question is "does a click actually land on it".
#
# It exists because the settings scrollbar could not be dragged and NOTHING
# about reading the source said why — three attempts at fixing it by eye all
# failed. mousePress/mouseDrag inside qmltestrunner answers that question in
# two seconds and without a compositor.
#
# The components under stubs/ are SYMLINKS to the real files. A copy would
# have passed happily while the shipping widget stayed broken.
set -e
cd "$(dirname "$0")"
RUNNER=/usr/lib/qt6/bin/qmltestrunner
[ -x "$RUNNER" ] || { echo "qmltestrunner not found (qt6-declarative)"; exit 1; }
QT_QPA_PLATFORM=offscreen "$RUNNER" -input . "$@"
