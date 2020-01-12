
# This tries to copy the generated shared library to ocaml.so in the
# current directory so that the import could work.
import os
import shutil
import sys
import time
import _thread
for src in ['_build/default/examples-async/ocaml_async.so']:
  if os.path.exists(src): shutil.copyfile(src, 'ocaml_async.so')
sys.path.append('.')

from ocaml_async import oasync, caml_start_scheduler

time.sleep(0.5)
def go():
  print('hello from python->ocaml/async->python', _thread.get_ident(), time.time())

caml_start_scheduler()
time.sleep(2.)
oasync.every('0.5s', go)
time.sleep(3.)
