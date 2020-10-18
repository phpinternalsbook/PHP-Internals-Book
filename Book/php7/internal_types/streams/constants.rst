.. _streams_open_options:

Streams open options
--------------------
  
These constants affect the operation of stream factory functions.

``IGNORE_PATH``
    This is the default option for streams; it requests that the include_path is
    not to be searched for the requested file.

``USE_PATH``
    Requests that the include_path is to be searched for the requested file.

``IGNORE_URL``
    Requests that registered URL wrappers are to be ignored when opening the
    stream.  Other non-URL wrappers will be taken into consideration when
    decoding the path.  There is no opposite form for this flag; the streams
    API will use all registered wrappers by default.

``IGNORE_URL_WIN``
    On Windows systems, this is equivalent to IGNORE_URL.
    On all other systems, this flag has no effect.

``ENFORCE_SAFE_MODE``
    Requests that the underlying stream implementation perform safe_mode
    checks on the file before opening the file.  Omitting this flag will skip
    safe_mode checks and allow opening of any file that the PHP process
    has rights to access.

``REPORT_ERRORS``
    If this flag is set, and there was an error during the opening of the file
    or URL, the streams API will call the php_error function for you.  This
    is useful because the path may contain username/password information
    that should not be displayed in the browser output (it would be a
    security risk to do so).  When the streams API raises the error, it first
    strips username/password information from the path, making the error
    message safe to display in the browser.

``STREAM_MUST_SEEK``
    This flag is useful when your extension really must be able to randomly
    seek around in a stream.  Some streams may not be seekable in their
    native form, so this flag asks the streams API to check to see if the
    stream does support seeking.  If it does not, it will copy the stream
    into temporary storage (which may be a temporary file or a memory
    stream) which does support seeking.
    Please note that this flag is not useful when you want to seek the
    stream and write to it, because the stream you are accessing might
    not be bound to the actual resource you requested.

.. note:: If the requested resource is network based, this flag will cause the
          opener to block until the whole contents have been downloaded.

``STREAM_WILL_CAST``
    If your extension is using a third-party library that expects a FILE* or
    file descriptor, you can use this flag to request the streams API to
    open the resource but avoid buffering.  You can then use
    ``php_stream_cast`` to retrieve the FILE* or
    file descriptor that the library requires.

    The is particularly useful when accessing HTTP URLs where the start
    of the actual stream data is found after an indeterminate offset into
    the stream.

    Since this option disables buffering at the streams API level, you
    may experience lower performance when using streams functions
    on the stream; this is deemed acceptable because you have told
    streams that you will be using the functions to match the underlying
    stream implementation.
    Only use this option when you are sure you need it.
