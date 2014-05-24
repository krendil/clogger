module clogger;

import std.logger;

import std.functional : unaryFun;
import std.array : back, empty, front, popBack, popFront, put, save; //Turn slices into ranges

template isCallableWith( alias fun, Args... ) {
    import std.typecons : Tuple;
    enum isCallableWith = __traits(compiles, fun(Tuple!(Args).init.expand));
}

private template isPredicate(alias fun, Arg) {
    enum bool isPredicate = isCallableWith!(fun, Arg) &&
                            is( typeof(fun(Arg.init)) == bool);
}

public template isLogFilter(alias filter) {
    enum bool isLogFilter = __traits(compiles, unaryFun!filter) &&
                            isPredicate!(unaryFun!filter, Logger.LoggerPayload);
}

public template isLogFormat(alias format) {
    enum bool isLogFormat = __traits(compiles, unaryFun!format) &&
                            isCallableWith!(format, Logger.LoggerPayload);
}

public template isLogSink(Sink, alias format) {
    import std.range : isOutputRange;
    enum bool isLogSink = isOutputRange!(Sink, typeof(unaryFun!format(Logger.LoggerPayload.init)));
}

/**
  * Customisable Logger
  */
public class Clogger(alias format, alias filter, Sink) : Logger
    if( isLogFilter!filter && isLogFormat!format && isLogSink!(Sink, format) )
{

    public this(Sink sink, string newName, LogLevel lv) {
        super(newName, lv);
        this.sink = sink;
    }

    override
    public void writeLogMsg(ref LoggerPayload payload) {
        import std.algorithm : copy;

        if( this.filterFun(payload) ) {
            sink = formatFun(payload).copy(sink);
        }
    }

    private:
    Sink sink;

    alias formatFun = unaryFun!format;
    alias filterFun = unaryFun!filter;

}

/**
  * Default/example log format, copied from std.logger
  */
private auto defaultFormat (Logger.LoggerPayload payload)  {
    import std.string;
    size_t fnIdx = payload.file.lastIndexOf('/');
    fnIdx = fnIdx == -1 ? 0 : fnIdx+1;
    size_t funIdx = payload.funcName.lastIndexOf('.');
    funIdx = funIdx == -1 ? 0 : funIdx+1;
    return format("%s:%s:%s:%u %s\n",payload.timestamp.toISOExtString(),
            payload.file[fnIdx .. $], payload.funcName[funIdx .. $],
            payload.line, payload.msg);
}

/**
  * Convenience creator function.
  */
public auto clogger(alias format = defaultFormat, alias filter = p => true, Sink)
    (Sink sink, string newName, LogLevel lv)
{
    return new Clogger!(format, filter, Sink)
                       (sink, newName, lv);
}

public auto stdoutClogger(string newName, LogLevel lv) {
    import std.stdio : stdout;
    return clogger(stdout.lockingTextWriter, newName, lv);
}

unittest {

    import std.algorithm, std.range, std.array;

    auto log = stdoutClogger("clogTest", LogLevel.all);

    log.trace("This is a test");



    dchar[100] buf;
    auto testMsg = "Log this string to that string!";
    auto testMsg2 = "Again!";

    auto stringLog = clogger!( p => p.msg )(buf[], "stringlog", LogLevel.all);
    
    stringLog.warning(testMsg);

    assert( buf[].startsWith(testMsg), "Failed to log basic message to string" );

    stringLog.warning(testMsg2);

    assert( buf[].startsWith(testMsg.chain(testMsg2)), "Failed to log second message to same sink" );

    buf[].initializeAll();

    auto pickyLog = clogger!( p => p.msg, p => (p.msg.length <= 10) )( buf[], "pickyLog", LogLevel.all);

    pickyLog.warning(testMsg);
    assert( !buf[].startsWith(testMsg), "Filter passed when it shouldn't have" );

    pickyLog.warning(testMsg2);
    assert( buf[].startsWith(testMsg2), "Filter failed when it shouldn't have" );

}
