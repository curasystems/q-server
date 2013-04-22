#
# It should be possible to upload package diffs
# 
# something along the lines of:
# 
# POST /packages/<packagename>/<previous-version>
# content-type: application/x-bspatch
# 
# the server would then attempt to batch the package
# and import it 