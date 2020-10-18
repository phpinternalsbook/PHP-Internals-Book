Streams File API Reference
--------------------------

php_stream_fopen_from_file
^^^^^^^^^^^^^^^^^^^^^^^^^^

Convert an ANSI FILE* into a stream::

    php_stream *php_stream_fopen_from_file(FILE *file, char *mode)

``php_stream_fopen_from_file`` returns a stream based on the
``file``. ``mode`` must be the same
as the mode used to open ``file``, otherwise strange errors
may occur when trying to write when the mode of the stream is different from the mode
on the file.

php_stream_fopen_tmpfile
^^^^^^^^^^^^^^^^^^^^^^^^

Open a FILE* with tmpfile() and convert into a stream::

    php_stream *php_stream_fopen_tmpfile(void)

``php_stream_fopen_tmpfile`` returns a stream based on a
temporary file opened with a mode of "w+b".  The temporary file will be deleted
automatically when the stream is closed or the process terminates.

php_stream_fopen_temporary_file
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Generate a temporary file name and open a stream on it::

    php_stream *php_stream_fopen_temporary_file(const char *dir, const char *pfx, char **opened)

``php_stream_fopen_temporary_file`` generates a temporary file name
in the directory specified by ``dir`` and with a prefix of ``pfx``.
The generated file name is returns in the ``opened`` parameter, which you
are responsible for cleaning up using ``efree``.
A stream is opened on that generated filename in "w+b" mode.
The file is NOT automatically deleted; you are responsible for unlinking or moving the file when you have
finished with it.
