
# This tries to copy the generated shared library to ocaml.so in the
# current directory so that the import could work.
import os
import shutil
import sys
import time
for src in ['_build/default/examples-async/ocaml_async.so']:
  if os.path.exists(src): shutil.copyfile(src, 'ocaml_async.so')
sys.path.append('.')

from ocaml_async import oasync, caml_start_scheduler

caml_start_scheduler()
time.sleep(3.)
print('here')
def go():
  print(time.time())

oasync.every('0.5s', go)
time.sleep(3.)
