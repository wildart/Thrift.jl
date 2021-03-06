import Base.TcpSocket, Base.TcpServer

type _enum_TTransportExceptionTypes
    UNKNOWN::Int32
    NOT_OPEN::Int32
    ALREADY_OPEN::Int32
    TIMED_OUT::Int32
    END_OF_FILE::Int32
end

const TransportExceptionTypes = _enum_TTransportExceptionTypes(int32(0), int32(1), int32(2), int32(3), int32(4))

type TTransportException <: Exception
    typ::Int32
    message::String

    TTransportException(typ=TransportExceptionTypes.UNKNOWN, message::String="") = new(typ, message)
end

# generic transport methods
read{T <: TTransport}(t::T, sz::Integer) = read(t, Array(Uint8, sz))
# TODO: can have more common methods by naming wrapped transports as io

# framed transport
type TFramedTransport <: TTransport
    tp::TTransport
    rbuff::IOBuffer
    wbuff::IOBuffer
    TFramedTransport(tp::TTransport) = new(tp, PipeBuffer(), PipeBuffer())
end
rawio(t::TFramedTransport)  = rawio(t.tp)
open(t::TFramedTransport)   = open(t.tp)
close(t::TFramedTransport)  = close(t.tp)
isopen(t::TFramedTransport) = isopen(t.tp)

_readframesz(t::TFramedTransport) = _read_fixed(rawio(t), uint32(0), 4, true)
function _readframe(t::TFramedTransport)
    sz = _readframesz(t)
    write(rbuff, read(t.tp, sz))
    nothing
end
function read(t::TFramedTransport, buff::Array{Uint8,1})
    (t.rbuff.size <= length(buff)) && (read(t.rbuff, buff); buff)
    _readframe(t)
    read(t, buff)
end

write(t::TFramedTransport, buff::Array{Uint8,1}) = (write(t.wbuff, buff); nothing)
function flush(t::TFramedTransport)
    szbuff = IOBuffer()
    _write_fixed(szbuff, uint32(t.wbuff.size), true)
    write(t.tp, takebuf_array(szbuff))
    write(t.tp, takebuf_array(wbuff))
    flush(t.tp)
end


# thrift socket transport 
type TSocket <: TTransport
    host::String
    port::Integer

    io::TcpSocket

    TSocket(host::String, port::Integer) = new(host, port)
    TSocket(port::Integer) = TSocket("127.0.0.1", port)
end

type TServerSocket <: TServerTransport
    host::String
    port::Integer

    io::TcpServer

    TServerSocket(host::String, port::Integer) = new(host, port)
    TServerSocket(port::Integer) = TServerSocket("", port)
end

typealias TSocketBase Union(TSocket, TServerSocket)

open(tsock::TServerSocket) = nothing
open(tsock::TSocket) = (!isopen(tsock) && (tsock.io = connect(tsock.host, tsock.port)); nothing)

listen(tsock::TServerSocket) = (tsock.io = isempty(tsock.host) ? listen(tsock.port) : listen(parseip(tsock.host), tsock.port); nothing)
function accept(tsock::TServerSocket) 
    accsock = TSocket(tsock.host, tsock.port)
    accsock.io = accept(tsock.io)
    accsock
end

close(tsock::TSocketBase) = (isopen(tsock.io) && close(tsock.io); nothing)
rawio(tsock::TSocketBase) = tsock.io
read(tsock::TSocketBase, buff::Array{Uint8,1}) = (read(tsock.io, buff); buff)
write(tsock::TSocketBase, buff::Array{Uint8,1}) = write(tsock.io, buff)
flush(tsock::TSocketBase)   = flush(tsock.io)
isopen(tsock::TSocketBase)  = (isdefined(tsock, :io) && isreadable(tsock.io) && iswritable(tsock.io))


