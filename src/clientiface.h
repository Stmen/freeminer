/*
Minetest
Copyright (C) 2010-2014 celeron55, Perttu Ahola <celeron55@gmail.com>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 2.1 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
*/
#ifndef _CLIENTIFACE_H_
#define _CLIENTIFACE_H_

#include "irr_v3d.h"                   // for irrlicht datatypes

#include "constants.h"
#include "serialization.h"             // for SER_FMT_VER_INVALID
#include "jthread/jmutex.h"

#include <list>
#include <vector>
#include <map>
#include <set>

#include <msgpack.hpp>

class MapBlock;
class ServerEnvironment;
class EmergeManager;

namespace con {
	class Connection;
}

enum ClientState
{
	Invalid,
	Disconnecting,
	Denied,
	Created,
	InitSent,
	InitDone,
	DefinitionsSent,
	Active
};

enum ClientStateEvent
{
	Init,
	GotInit2,
	SetDenied,
	SetDefinitionsSent,
	SetMediaSent,
	Disconnect
};

/*
	Used for queueing and sorting block transfers in containers

	Lower priority number means higher priority.
*/
struct PrioritySortedBlockTransfer
{
	PrioritySortedBlockTransfer(float a_priority, v3s16 a_pos, u16 a_peer_id)
	{
		priority = a_priority;
		pos = a_pos;
		peer_id = a_peer_id;
	}
	bool operator < (const PrioritySortedBlockTransfer &other) const
	{
		return priority < other.priority;
	}
	float priority;
	v3s16 pos;
	u16 peer_id;
};

class RemoteClient
{
public:
	// peer_id=0 means this client has no associated peer
	// NOTE: If client is made allowed to exist while peer doesn't,
	//       this has to be set to 0 when there is no peer.
	//       Also, the client must be moved to some other container.
	u16 peer_id;
	// The serialization version to use with the client
	u8 serialization_version;
	//
	u16 net_proto_version;

	s16 m_nearest_unsent_nearest;
	s16 wanted_range;

	RemoteClient():
		peer_id(PEER_ID_INEXISTENT),
		serialization_version(SER_FMT_VER_INVALID),
		net_proto_version(0),
		m_nearest_unsent_nearest(0),
		wanted_range(9 * MAP_BLOCKSIZE),
		m_time_from_building(9999),
		m_pending_serialization_version(SER_FMT_VER_INVALID),
		m_state(Created),
		m_nearest_unsent_d(0),
		m_nearest_unsent_reset_timer(0.0),
		m_excess_gotblocks(0),
		m_nothing_to_send_counter(0),
		m_nothing_to_send_pause_timer(0.0),
		m_name("")
	{
	}
	~RemoteClient()
	{
	}

	/*
		Finds block that should be sent next to the client.
		Environment should be locked when this is called.
		dtime is used for resetting send radius at slow interval
	*/
	void GetNextBlocks(ServerEnvironment *env, EmergeManager* emerge,
			float dtime, std::vector<PrioritySortedBlockTransfer> &dest);

	void GotBlock(v3s16 p);

	void SentBlock(v3s16 p);

	void SetBlockNotSent(v3s16 p);
	void SetBlocksNotSent(std::map<v3s16, MapBlock*> &blocks);

	s32 SendingCount()
	{
		return m_blocks_sending.size();
	}

	// Increments timeouts and removes timed-out blocks from list
	// NOTE: This doesn't fix the server-not-sending-block bug
	//       because it is related to emerging, not sending.
	//void RunSendingTimeouts(float dtime, float timeout);

	void PrintInfo(std::ostream &o)
	{
		o<<"RemoteClient "<<peer_id<<": "
				<<"m_blocks_sent.size()="<<m_blocks_sent.size()
				<<", m_blocks_sending.size()="<<m_blocks_sending.size()
				<<", m_nearest_unsent_d="<<m_nearest_unsent_d
				<<", m_excess_gotblocks="<<m_excess_gotblocks
				<<std::endl;
		m_excess_gotblocks = 0;
	}

	// Time from last placing or removing blocks
	float m_time_from_building;

	/*
		List of active objects that the client knows of.
		Value is dummy.
	*/
	std::set<u16> m_known_objects;

	ClientState getState()
		{ return m_state; }

	std::string getName()
		{ return m_name; }

	void setName(std::string name)
		{ m_name = name; }

	/* update internal client state */
	void notifyEvent(ClientStateEvent event);

	/* set expected serialization version */
	void setPendingSerializationVersion(u8 version)
		{ m_pending_serialization_version = version; }

	void confirmSerializationVersion()
		{ serialization_version = m_pending_serialization_version; }

private:
	// Version is stored in here after INIT before INIT2
	u8 m_pending_serialization_version;

	/* current state of client */
	ClientState m_state;

	/*
		Blocks that have been sent to client.
		- These don't have to be sent again.
		- A block is cleared from here when client says it has
		  deleted it from it's memory

		Key is position, value is dummy.
		No MapBlock* is stored here because the blocks can get deleted.
	*/
	std::set<v3s16> m_blocks_sent;

public:
	s16 m_nearest_unsent_d;
private:

	v3s16 m_last_center;
	float m_nearest_unsent_reset_timer;

	/*
		Blocks that are currently on the line.
		This is used for throttling the sending of blocks.
		- The size of this list is limited to some value
		Block is added when it is sent with BLOCKDATA.
		Block is removed when GOTBLOCKS is received.
		Value is time from sending. (not used at the moment)
	*/
	std::map<v3s16, float> m_blocks_sending;

	/*
		Count of excess GotBlocks().
		There is an excess amount because the client sometimes
		gets a block so late that the server sends it again,
		and the client then sends two GOTBLOCKs.
		This is resetted by PrintInfo()
	*/
	u32 m_excess_gotblocks;

	// CPU usage optimization
	u32 m_nothing_to_send_counter;
	float m_nothing_to_send_pause_timer;
	std::string m_name;
};

class ClientInterface {
public:

	friend class Server;

	ClientInterface(con::Connection* con);
	~ClientInterface();

	/* run sync step */
	void step(float dtime);

	/* get list of active client id's */
	std::list<u16> getClientIDs(ClientState min_state=Active);

	/* get list of client player names */
	std::vector<std::string> getPlayerNames();

	/* send message to client */
	void send(u16 peer_id, u8 channelnum, SharedBuffer<u8> data, bool reliable);

	/* send message to client */
	void send(u16 peer_id, u8 channelnum, const msgpack::sbuffer &data, bool reliable);

	/* send to all clients */
	void sendToAll(u16 channelnum, SharedBuffer<u8> data, bool reliable);
	void sendToAll(u16 channelnum, msgpack::sbuffer const &buffer, bool reliable);

	/* delete a client */
	void DeleteClient(u16 peer_id);

	/* create client */
	void CreateClient(u16 peer_id);

	/* get a client by peer_id */
	RemoteClient* getClientNoEx(u16 peer_id,  ClientState state_min=Active);

	/* get client by peer_id (make sure you have list lock before!*/
	RemoteClient* lockedGetClientNoEx(u16 peer_id,  ClientState state_min=Active);

	/* get state of client by id*/
	ClientState getClientState(u16 peer_id);

	/* set client playername */
	void setPlayerName(u16 peer_id,std::string name);

	/* get protocol version of client */
	u16 getProtocolVersion(u16 peer_id);

	/* event to update client state */
	void event(u16 peer_id, ClientStateEvent event);

	/* set environment */
	void setEnv(ServerEnvironment* env)
	{ assert(m_env == 0); m_env = env; }

protected:
	//TODO find way to avoid this functions
	void Lock()
		{ m_clients_mutex.Lock(); }
	void Unlock()
		{ m_clients_mutex.Unlock(); }

public:
	std::map<u16, RemoteClient*>& getClientList()
		{ return m_clients; }

private:
	/* update internal player list */
	void UpdatePlayerList();

	// Connection
	con::Connection* m_con;
	JMutex m_clients_mutex;
	// Connected clients (behind the con mutex)
	std::map<u16, RemoteClient*> m_clients;
	std::vector<std::string> m_clients_names; //for announcing masterserver

	// Environment
	ServerEnvironment *m_env;
	JMutex m_env_mutex;

	float m_print_info_timer;
};

#endif
