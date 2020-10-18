Streams Common API Reference
----------------------------

php_stream_stat_path
^^^^^^^^^^^^^^^^^^^^

Get the status for a file or URL::

    int php_stream_stat_path(char *path, php_stream_statbuf *ssb)

``php_stream_stat_path`` examines the file or URL specified by ``path``
and returns information such as file size, access and creation times and so on.
The return value is 0 on success, -1 on error.
For more information about the information returned, see :ref:`php_stream_statbuf`.

php_stream_stat
^^^^^^^^^^^^^^^

Get the status for the underlying storage associated with a stream::

    int php_stream_stat(php_stream *stream, php_stream_statbuf *ssb)

``php_stream_stat`` examines the storage to which ``stream``
is bound, and returns information such as file size, access and creation times and so on.
The return value is 0 on success, -1 on error.
For more information about the information returned, see :ref:`php_stream_statbuf`.

php_stream_open_wrapper
^^^^^^^^^^^^^^^^^^^^^^^

Open a stream on a file or URL::

    php_stream *php_stream_open_wrapper(char *path, char *mode, int options, char **opened)

``php_stream_open_wrapper`` opens a stream on the file, URL or
other wrapped resource specified by ``path``.  Depending on
the value of ``mode``, the stream may be opened for reading,
writing, appending or combinations of those. See the table below for the different
modes that can be used; in addition to the characters listed below, you may
include the character 'b' either as the second or last character in the mode string.
The presence of the 'b' character informs the relevant stream implementation to
open the stream in a binary safe mode.

The 'b' character is ignored on all POSIX conforming systems which treat
binary and text files in the same way.  It is a good idea to specify the 'b'
character whenever your stream is accessing data where the full 8 bits
are important, so that your code will work when compiled on a system
where the 'b' flag is important.

Any local files created by the streams API will have their initial permissions set
according to the operating system defaults - under Unix based systems
this means that the umask of the process will be used.  Under Windows,
the file will be owned by the creating process.
Any remote files will be created according to the URL wrapper that was
used to open the file, and the credentials supplied to the remote server.

``r``
    Open text file for reading.  The stream is positioned at the beginning of
    the file.

``r+``
    Open text file for reading and writing.  The stream is positioned at the beginning of
    the file.

``w``
    Truncate the file to zero length or create text file for writing.
    The stream is positioned at the beginning of the file.

``w+``
    Open text file for reading and writing.  The file is created if
    it does not exist, otherwise it is truncated. The stream is positioned at
    the beginning of the file.

``a``
    Open for writing.  The file is created if it does not exist.
    The stream is positioned at the end of the file.

``a+``
    Open text file for reading and writing.  The file is created if
    it does not exist. The stream is positioned at the end of the file.

``options`` affects how the path/URL of the stream is
interpreted, safe mode checks and actions taken if there is an error during opening
of the stream.  See :ref:`streams_open_options` for
more information about options.

If ``opened`` is not NULL, it will be set to a string containing
the name of the actual file/resource that was opened.  This is important when the
options include ``USE_PATH``, which causes the include_path to be searched for the
file.  You, the caller, are responsible for calling ``efree`` on
the filename returned in this parameter.

.. note::
    If you specified ``STREAM_MUST_SEEK`` in ``options``,
    the path returned in ``opened`` may not be the name of the
    actual stream that was returned to you.  It will, however, be the name of the original
    resource from which the seekable stream was manufactured.

php_stream_read
^^^^^^^^^^^^^^^

Read a number of bytes from a stream into a buffer::

    size_t php_stream_read(php_stream *stream, char *buf, size_t count)

``php_stream_read`` reads up to ``count``
bytes of data from ``stream`` and copies them into the
buffer ``buf``.

``php_stream_read`` returns the number of bytes that were
read successfully.  There is no distinction between a failed read or an end-of-file
condition – use ``php_stream_eof`` to test for an ``EOF``.

The internal position of the stream is advanced by the number of bytes that were
read, so that subsequent reads will continue reading from that point.

If less than ``count`` bytes are available to be read, this
call will block (or wait) until the required number are available, depending on the
blocking status of the stream.  By default, a stream is opened in blocking mode.
When reading from regular files, the blocking mode will not usually make any
difference: when the stream reaches the ``EOF``
``php_stream_read`` will return a value less than
``count``, and 0 on subsequent reads.

php_stream_write
^^^^^^^^^^^^^^^^

Write a number of bytes from a buffer to a stream::

    size_t php_stream_write(php_stream *stream, const char *buf, size_t count)

``php_stream_write`` writes ``count``
bytes of data from ``buf`` into ``stream``.

``php_stream_write`` returns the number of bytes that were
written successfully.  If there was an error, the number of bytes written will be
less than ``count``.

The internal position of the stream is advanced by the number of bytes that were
written, so that subsequent writes will continue writing from that point.

php_stream_eof
^^^^^^^^^^^^^^

Check for an end-of-file condition on a stream::

    int php_stream_eof(php_stream *stream)

``php_stream_eof`` checks for an end-of-file condition
on ``stream``.

``php_stream_eof`` returns the 1 to indicate
``EOF``, 0 if there is no ``EOF`` and -1 to indicate an error.

php_stream_getc
^^^^^^^^^^^^^^^

Read a single byte from a stream::

    int php_stream_getc(php_stream *stream)

``php_stream_getc`` reads a single character from
``stream`` and returns it as an unsigned char cast
as an int, or ``EOF`` if the end-of-file is reached, or an error occurred.

``php_stream_getc`` may block in the same way as
``php_stream_read`` blocks.

The internal position of the stream is advanced by 1 if successful.

php_stream_gets
^^^^^^^^^^^^^^^

Read a line of data from a stream into a buffer::

    char *php_stream_gets(php_stream *stream, char *buf, size_t maxlen)

``php_stream_gets`` reads up to ``count``-1
bytes of data from ``stream`` and copies them into the
buffer ``buf``.  Reading stops after an ``EOF``
or a newline.  If a newline is read, it is stored in ``buf`` as part of
the returned data.  A NUL terminating character is stored as the last character
in the buffer.

``php_stream_read`` returns ``buf``
when successful or NULL otherwise.

The internal position of the stream is advanced by the number of bytes that were
read, so that subsequent reads will continue reading from that point.

This function may block in the same way as ``php_stream_read``.

php_stream_close
^^^^^^^^^^^^^^^^

Close a stream::

    int php_stream_close(php_stream *stream)

``php_stream_close`` safely closes ``stream``
and releases the resources associated with it.  After ``stream``
has been closed, it's value is undefined and should not be used.

``php_stream_close`` returns 0 if the stream was closed or
``EOF``  to indicate an error.  Regardless of the success of the call,
``stream`` is undefined and should not be used after a call to
this function.

php_stream_flush
^^^^^^^^^^^^^^^^

Flush stream buffers to storage::

    int php_stream_flush(php_stream *stream)

``php_stream_flush`` causes any data held in
write buffers in ``stream`` to be committed to the
underlying storage.

``php_stream_flush`` returns 0 if the buffers were flushed,
or if the buffers did not need to be flushed, but returns ``EOF`` 
to indicate an error.

php_stream_seek
^^^^^^^^^^^^^^^

Reposition a stream::

    int php_stream_seek(php_stream *stream, off_t offset, int whence)

``php_stream_seek`` repositions the internal
position of ``stream``.
The new position is determined by adding the ``offset``
to the position indicated by ``whence``.
If ``whence`` is set to ``SEEK_SET``,
``SEEK_CUR`` or ``SEEK_END`` the offset
is relative to the start of the stream, the current position or the end of the stream, respectively.

``php_stream_seek`` returns 0 on success, but -1 if there was an error.

.. note:: 
    Not all streams support seeking, although the streams API will emulate a seek if
    ``whence`` is set to ``SEEK_CUR``
    and ``offset`` is positive, by calling ``php_stream_read``
    to read (and discard) ``offset`` bytes.

    The emulation is only applied when the underlying stream implementation does not
    support seeking.  If the stream is (for example) a file based stream that is wrapping
    a non-seekable pipe, the streams api will not apply emulation because the file based
    stream implements a seek operation; the seek will fail and an error result will be
    returned to the caller.

php_stream_tell
^^^^^^^^^^^^^^^

Determine the position of a stream::

    off_t php_stream_tell(php_stream *stream)

``php_stream_tell`` returns the internal position of
``stream``, relative to the start of the stream.
If there is an error, -1 is returned.

php_stream_copy_to_stream
^^^^^^^^^^^^^^^^^^^^^^^^^

Copy data from one stream to another::

    size_t php_stream_copy_to_stream(php_stream *src, php_stream *dest, size_t maxlen)

``php_stream_copy_to_stream`` attempts to read up to ``maxlen``
bytes of data from ``src`` and write them to ``dest``,
and returns the number of bytes that were successfully copied.

If you want to copy all remaining data from the ``src`` stream, pass the
constant ``PHP_STREAM_COPY_ALL`` as the value of ``maxlen``.

.. note::
    This function will attempt to copy the data in the most efficient manner, using memory mapped
    files when possible.

php_stream_copy_to_mem
^^^^^^^^^^^^^^^^^^^^^^

Copy data from stream and into an allocated buffer::

    size_t php_stream_copy_to_mem(php_stream *src, char **buf, size_t maxlen, int persistent)

``php_stream_copy_to_mem`` allocates a buffer ``maxlen``+1
bytes in length using ``pemalloc`` (passing ``persistent``).
It then reads ``maxlen`` bytes from ``src`` and stores
them in the allocated buffer.

The allocated buffer is returned in ``buf``, and the number of bytes successfully
read.  You, the caller, are responsible for freeing the buffer by passing it and ``persistent``
to ``pefree``.

If you want to copy all remaining data from the ``src`` stream, pass the
constant ``PHP_STREAM_COPY_ALL`` as the value of ``maxlen``.

.. note::
    This function will attempt to copy the data in the most efficient manner, using memory mapped
    files when possible.

php_stream_make_seekable
^^^^^^^^^^^^^^^^^^^^^^^^

Convert a stream into a stream is seekable::

    int php_stream_make_seekable(php_stream *origstream, php_stream **newstream, int flags)

``php_stream_make_seekable`` checks if ``origstream`` is
seekable.   If it is not, it will copy the data into a new temporary stream.
If successful, ``newstream`` is always set to the stream that is valid to use, even if the original
stream was seekable.

``flags`` allows you to specify your preference for the seekable stream that is
returned: use ``PHP_STREAM_NO_PREFERENCE`` to use the default seekable stream
(which uses a dynamically expanding memory buffer, but switches to temporary file backed storage
when the stream size becomes large), or use ``PHP_STREAM_PREFER_STDIO`` to
use "regular" temporary file backed storage.

``php_stream_make_seekable`` return values

``PHP_STREAM_UNCHANGED``
    Original stream was seekable anyway. ``newstream`` is set to the value
    of ``origstream``.

``PHP_STREAM_RELEASED``
    Original stream was not seekable and has been released. ``newstream`` is set to the
    new seekable stream.  You should not access ``origstream`` anymore.

``PHP_STREAM_FAILED``
    An error occurred while attempting conversion. ``newstream`` is set to NULL;
    ``origstream`` is still valid.

``PHP_STREAM_CRITICAL``
    An error occurred while attempting conversion that has left ``origstream`` in
    an indeterminate state. ``newstream`` is set to NULL and it is highly recommended
    that you close ``origstream``.

.. note::
    If you need to seek and write to the stream, it does not make sense to use this function, because the stream
    it returns is not guaranteed to be bound to the same resource as the original stream.

.. note::
    If you only need to seek forwards, there is no need to call this function, as the streams API will emulate
    forward seeks when the whence parameter is ``SEEK_CUR``.

.. note::
    If ``origstream`` is network based, this function will block until the whole contents
    have been downloaded.

.. note::
    NEVER call this function with an ``origstream`` that is reference by a file pointer
    in a PHP script!  This function may cause the underlying stream to be closed which could cause a crash
    when the script next accesses the file pointer!

.. note::
    In many cases, this function can only succeed when ``origstream`` is a newly opened
    stream with no data buffered in the stream layer.  For that reason, and because this function is complicated to
    use correctly, it is recommended that you use ``php_stream_open_wrapper`` and pass in
    ``PHP_STREAM_MUST_SEEK`` in your options instead of calling this function directly.

php_stream_cast
^^^^^^^^^^^^^^^

Convert a stream into another form, such as a FILE* or socket::

    int php_stream_cast(php_stream *stream, int castas, void **ret, intflags)

``php_stream_cast`` attempts to convert ``stream`` into
a resource indicated by ``castas``.
If ``ret`` is NULL, the stream is queried to find out if such a conversion is
possible, without actually performing the conversion (however, some internal stream state *might*
be changed in this case).
If ``flags`` is set to ``REPORT_ERRORS``, an error
message will be displayed is there is an error during conversion.

.. note::
    This function returns ``SUCCESS`` for success or ``FAILURE``
    for failure.  Be warned that you must explicitly compare the return value with ``SUCCESS``
    or ``FAILURE`` because of the underlying values of those constants. A simple
    boolean expression will not be interpreted as you intended.

Resource types for ``castas``

``PHP_STREAM_AS_STDIO``
    Requests an ANSI FILE* that represents the stream

``PHP_STREAM_AS_FD``
    Requests a POSIX file descriptor that represents the stream

``PHP_STREAM_AS_SOCKETD``
    Requests a network socket descriptor that represents the stream

In addition to the basic resource types above, the conversion process can be altered by using the
following flags by using the OR operator to combine the resource type with one or more of the
following values:

Resource types for ``castas``

``PHP_STREAM_CAST_TRY_HARD``
    Tries as hard as possible, at the expense of additional resources, to ensure that the conversion succeeds

``PHP_STREAM_CAST_RELEASE``
    Informs the streams API that some other code (possibly a third party library) will be responsible for closing the
    underlying handle/resource.  This causes the ``stream`` to be closed in such a way the underlying
    handle is preserved and returned in ``ret``.  If this function succeeds, ``stream``
    should be considered closed and should no longer be used.

.. note::
    If your system supports ``fopencookie`` (systems using glibc 2 or later), the streams API
    will always be able to synthesize an ANSI FILE* pointer over any stream.
    While this is tremendously useful for passing any PHP stream to any third-party libraries, such behaviour is not
    portable.  You are requested to consider the portability implications before distributing you extension.
    If the fopencookie synthesis is not desirable, you should query the stream to see if it naturally supports FILE*
    by using ``php_stream_is``

.. note::
    If you ask a socket based stream for a FILE*, the streams API will use ``fdopen`` to
    create it for you.  Be warned that doing so may cause data that was buffered in the streams layer to be
    lost if you intermix streams API calls with ANSI stdio calls.

See also ``php_stream_is`` and ``php_stream_can_cast``.
 
php_stream_can_cast
^^^^^^^^^^^^^^^^^^^

Determines if a stream can be converted into another form, such as a FILE* or socket::

    int php_stream_can_cast(php_stream *stream, int castas)

This function is equivalent to calling ``php_stream_cast`` with ``ret``
set to NULL and ``flags`` set to 0.
It returns ``SUCCESS`` if the stream can be converted into the form requested, or
``FAILURE`` if the conversion cannot be performed.

.. note::
    Although this function will not perform the conversion, some internal stream state *might* be
    changed by this call.

.. note::
    You must explicitly compare the return value of this function with one of the constants, as described
    in ``php_stream_cast``.

See also ``php_stream_cast`` and ``php_stream_is``.

php_stream_is_persistent
^^^^^^^^^^^^^^^^^^^^^^^^

Determines if a stream is a persistent stream::

    int php_stream_is_persistent(php_stream *stream)

``php_stream_is_persistent`` returns 1 if the stream is a persistent stream,
0 otherwise.

php_stream_is
^^^^^^^^^^^^^

Determines if a stream is of a particular type::

    int php_stream_is(php_stream *stream, int istype)

``php_stream_is`` returns 1 if ``stream`` is of
the type specified by ``istype``, or 0 otherwise.

Values for ``istype``

``PHP_STREAM_IS_STDIO``
    The stream is implemented using the stdio implementation

``PHP_STREAM_IS_SOCKET``
    The stream is implemented using the network socket implementation

``PHP_STREAM_IS_USERSPACE``
    The stream is implemented using the userspace object implementation

``PHP_STREAM_IS_MEMORY``
    The stream is implemented using the grow-on-demand memory stream implementation

.. note::
    The PHP_STREAM_IS_XXX "constants" are actually defined as pointers to the underlying
    stream operations structure.  If your extension (or some other extension) defines additional
    streams, it should also declare a PHP_STREAM_IS_XXX constant in it's header file that you
    can use as the basis of this comparison.

.. note::
    This function is implemented as a simple (and fast) pointer comparison, and does not change
    the stream state in any way.

See also ``php_stream_cast`` and ``php_stream_can_cast``.

php_stream_passthru
^^^^^^^^^^^^^^^^^^^

Outputs all remaining data from a stream::

    size_t php_stream_passthru(php_stream *stream)

``php_stream_passthru`` outputs all remaining data from ``stream``
to the active output buffer and returns the number of bytes output.
If buffering is disabled, the data is written straight to the output, which is the browser making the
request in the case of PHP on a web server, or stdout for CLI based PHP.
This function will use memory mapped files if possible to help improve performance.

php_register_url_stream_wrapper
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Registers a wrapper with the Streams API::

    int php_register_url_stream_wrapper(char *protocol, php_stream_wrapper *wrapper, TSRMLS_DC)

``php_register_url_stream_wrapper`` registers ``wrapper``
as the handler for the protocol specified by ``protocol``.

.. note::
    If you call this function from a loadable module, you *MUST* call ``php_unregister_url_stream_wrapper``
    in your module shutdown function, otherwise PHP will crash.

php_unregister_url_stream_wrapper
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Unregisters a wrapper from the Streams API::

    int php_unregister_url_stream_wrapper(char *protocol, TSRMLS_DC)

``php_unregister_url_stream_wrapper`` unregisters the wrapper
associated with ``protocol``.

php_stream_open_wrapper_ex
^^^^^^^^^^^^^^^^^^^^^^^^^^

Opens a stream on a file or URL, specifying context::

    php_stream *php_stream_open_wrapper_ex(char *path, char *mode, int options, char **opened, php_stream_context *context)

``php_stream_open_wrapper_ex`` is exactly like
``php_stream_open_wrapper``, but allows you to specify a
php_stream_context object using ``context``.
To find out more about stream contexts,
see `Stream Contexts <https://www.php.net/manual/en/stream.contexts.php>`_.

php_stream_open_wrapper_as_file
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Opens a stream on a file or URL, and converts to a FILE*::

    FILE * php_stream_open_wrapper_as_file(char *path, char *mode, int options, char **opened)

``php_stream_open_wrapper_as_file`` is exactly like
``php_stream_open_wrapper``, but converts the stream
into an ANSI stdio FILE* and returns that instead of the stream.
This is a convenient shortcut for extensions that pass FILE* to third-party libraries.

php_stream_filter_register_factory
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Registers a filter factory with the Streams API::

    int php_stream_filter_register_factory(const char *filterpattern, php_stream_filter_factory *factory)

Use this function to register a filter factory with the name given by
``filterpattern``.  ``filterpattern``
can be either a normal string name (i.e. ``myfilter``) or
a global pattern (i.e. ``myfilterclass.*``) to allow a single
filter to perform different operations depending on the exact name of the filter
invoked (i.e. ``myfilterclass.foo``, ``myfilterclass.bar``,
etc...)

.. note::
    Filters registered by a loadable extension must be certain to call
    php_stream_filter_unregister_factory() during MSHUTDOWN.

php_stream_filter_unregister_factory
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Deregisters a filter factory with the Streams API::

    int php_stream_filter_unregister_factory(const char *filterpattern)

Deregisters the ``filterfactory`` specified by the
``filterpattern`` making it no longer available for use.

.. note::
    Filters registered by a loadable extension must be certain to call
    php_stream_filter_unregister_factory() during MSHUTDOWN.
