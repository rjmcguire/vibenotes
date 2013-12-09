module vibenotes.broadcast;

import vibe.core.core;
import vibe.core.log;
import vibe.http.server;
import vibe.http.websockets;
import vibe.core.sync;

class WebSocketBroadcastService {
	private {
		LockableManualEvent m_signal;
		string[][WebSocket] m_queues;
		string[WebSocket] m_channels;
	}

	this() {
		m_signal = cast(LockableManualEvent)createManualEvent();
	}

	void handleRequest(HTTPServerRequest req, HTTPServerResponse res) {
		auto pv = "channel" in req.params;
		auto channel = pv ? *pv : "default";

		logInfo("Channel: %s", channel);
		auto callback = handleWebSockets( (socket) {
			m_queues[socket] = [];
			m_channels[socket] = channel;
			m_signal.acquire();
			while( socket.connected ) {
				if( socket.dataAvailableForRead() ) {
					auto data = socket.receiveBinary();
					foreach( s, ref q ; m_queues ) {
						auto pc = s in m_channels;
						if( s !is socket && pc && *pc == channel ) q ~= cast(string)data;
					}
					m_signal.emit();
				}

				foreach( message ; m_queues[socket] ) {
					socket.send(cast(ubyte[])message);
				}
				m_queues[socket] = [];
				rawYield();
			}
			m_signal.release();
			m_queues.remove(socket);
		});

		callback(req, res);
	}
	
	@property string[] channels() const {
		int[string] chann;
		foreach(WebSocket k, v; m_channels)
			if( !(v in chann) )
				chann[v] = 1;
		return chann.keys;
	}		
}
/// Non standard helper interface !!! seriously don't use it !!!
interface LockableManualEvent:ManualEvent {
	/// Releases the ownership of the object.
	void release();
	
	/// Acquires the ownership of an unowned object.
	void acquire();
	
	/// Returns true if the calling fiber owns this object
	bool amOwner();
}