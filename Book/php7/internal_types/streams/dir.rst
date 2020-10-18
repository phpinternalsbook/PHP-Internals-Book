Streams Dir API Reference
-------------------------

The functions listed in this section work on local files, as well as remote files
(provided that the wrapper supports this functionality!).

php_stream_opendir
^^^^^^^^^^^^^^^^^^

Open a directory for file enumeration::

    php_stream * php_stream_opendir(char *path, php_stream_context *context)

``php_stream_opendir`` returns a stream that can be used to list the
files that are contained in the directory specified by ``path``.
This function is functionally equivalent to POSIX ``opendir``.
Although this function returns a php_stream object, it is not recommended to
try to use the functions from the common API on these streams.

php_stream_readdir
^^^^^^^^^^^^^^^^^^

Fetch the next directory entry from an opened dir::

    php_stream_dirent *php_stream_readdir(php_stream *dirstream, php_stream_dirent *ent)

``php_stream_readdir`` reads the next directory entry
from ``dirstream`` and stores it into ``ent``.
If the function succeeds, the return value is ``ent``.
If the function fails, the return value is NULL.
See :ref:`php_stream_dirent` for more
details about the information returned for each directory entry.

php_stream_rewinddir
^^^^^^^^^^^^^^^^^^^^

Rewind a directory stream to the first entry::

    int php_stream_rewinddir(php_stream *dirstream)

``php_stream_rewinddir`` rewinds a directory stream to the first entry.
Returns 0 on success, but -1 on failure.

php_stream_closedir
^^^^^^^^^^^^^^^^^^^

Close a directory stream and release resources::

    int php_stream_closedir(php_stream *dirstream)

``php_stream_closedir`` closes a directory stream and releases
resources associated with it.
Returns 0 on success, but -1 on failure.
