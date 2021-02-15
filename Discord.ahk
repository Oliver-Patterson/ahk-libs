;; ? Modified from https://github.com/G33kDude/Discord.ahk
#include <WebSocket>
#include <requests>

class Discord {
	static OPCode := {0: "Dispatch"
					,1: "Heartbeat"
					,2: "Identify"
					,3: "PresenceUpdate"
					,4: "VoiceStateUpdate"
					,5: ""
					,6: "Resume"
					,7: "Reconnect"
					,8: "RequestGuildMembers"
					,9: "InvalidSession"
					,10: "Hello"
					,11: "HeartbeatACK"}
	reconnects := 0

	__New(parent, token, intents, owner_guild := "", owner_id := "") {
		;; ? owner guild is required for checking when the bot has loaded the owner's guild so it can use those emotes at start
		;; ? owner guild and owner id are used to add .isGuildOwner and .isBotOwner to the ctx
		this.utils.init(this)
		this.cache.init(this)
		this.intents := intents
		this.token := token
		this.owner := {guild: owner_guild, id: owner_id}
		this.creator := parent
		this.ratelimit := {}
		this.connect()
	}

	setResume(sessionid, seq) {
		this.resumedata := {session: sessionid, seq: seq}
	}

	connect() {
		try {
			data := this.CallAPI("GET", "gateway/bot")
			debug.print("[DISCORD] " data.session_start_limit.remaining "/" data.session_start_limit.total " identifies")
			this.ws := new WebSocket(this, data.url "?v=8&encoding=json")
		} catch {
			return 1
		}
		this.last_reconnect := A_TickCount
	}

	disconnect() {
		this.connected := false
		this.ws.disconnect()
		this.ws := ""
	}

	reconnect(useResume := false) {
		static TIMEOUT := 60*1000
		debug.print("[Reconnect] total: " this.reconnects)
		this.disconnect()
		if (this.last_reconnect+TIMEOUT > A_TickCount)
			Throw Exception("Wont reconnect")

		if (useResume && this.session_id)
			this.setResume(this.session_id, this.seq)

		while !this.connect() {
			debug.print("[Reconnect] Trying to reconnect #" A_Index)
			sleep % 5*Min(A_Index, 120)*1000
		}

		this.reconnects++
	}

	delete() {
		this.ws.disconnect()
		this.creator := false
	}

	class cache {
		guild := {}
		user := {}
		dm := {}
		msg := {}

		init(byref parent) {
			this.api := parent
		}

		userGet(id) {
			for _, guild in this.guild {
				if index := this.memberGet(guild.id, id)
					return guild.members[index].user
			}
			Throw Exception("No user found with id " id, -2)
		}

		dmGet(id) {
			return this.dm[id]
		}

		dmSet(id, data) {
			this.dm[id] := data
		}

		channelGet(guild, id) {
			for i, channel in this.guildGet(guild).channels {
				if (channel.id = id)
					return i
			}
		}

		channelUpdate(guild, id, data) {
			index := this.channelGet(guild, id)
			this.guild[guild].channels[index] := data
		}

		channelDelete(guild, id) {
			this.guildGet(guild).channels.RemoveAt(this.channelGet(guild, id))
		}

		channelSet(guild, data) {
			this.guildGet(guild).channels.InsertAt(1, data)
		}

		memberGet(guild, id) {
			for i, member in this.guildGet(guild).members
				if (member.user.id = id)
					return i

		}

		memberDelete(guild, id) {
			index := this.memberGet(guild, id)
			this.guildGet(guild).members.RemoveAt(index)
		}

		memberUpdate(guild, id, member) {
			index := this.memberGet(guild, id)
			newm := this.guildGet(guild).members[index] := member
			newm.roles.push(guild)
		}

		memberSet(guild, member) {
			newm := this.guildGet(guild).members.InsertAt(1, member)
			newm.roles.push(guild)
		}

		guildSet(guild, data) {
			this.guild[guild] := data
			for _, value in this.guild[guild].members {
				index := this.memberGet(guild, value.user.id)
				member := this.guild[guild].members[index]
				for _, role in member.roles {
					if role = guild
						break
				}
				member.roles.push(guild)
			}
		}

		guildUpdate(guild, data) {
			this.guild[guild] := ObjectMerge(data, this.guild[guild])
		}

		guildGet(id) {
			return this.guild[id]
		}

		guildDelete(id) {
			this.guild.Delete(id)
		}

		roleUpdate(guild, id, data) {
			index := this.roleGet(guild, id)
			this.guild[guild].roles[index] := data
		}

		roleDelete(guild, id) {
			for _, role in this.getGuild(guild).roles {
				if (role.id = data.d.role_id) {
					this.guild[guild].roles.RemoveAt(A_Index)
					return
				}
			}
		}

		roleCreate(guild, role) {
			this.guild[guild].roles.push(role)
		}

		roleGet(guild, id) {
			for i, role in this.guildGet(guild).roles
				if (role.id = id)
					return i
		}

		messageSet(channel, data) {
			if !this.msg[channel]
				this.msg[channel] := {}

			this.msg[channel][data.id] := data
		}

		messageGet(channel, id) {
			return this.msg[channel][id]
		}

		emojiGet(guild, name) {
			for _, value in this.guildGet(guild).emojis
				if (value.name = name)
					return value
			Throw Exception("Couldn't find emoji", -2, name)
		}

		emojiUpdate(guild, emojis) {
			this.guildGet(guild).emojis := emojis
		}
	}

	class utils {
		init(byref parent) {
			this.api := parent
		}

		sendWebhook(content, webhook) {
			http := new requests("POST", webhook,, true)
			http.headers["Content-Type"] := "application/json"
			http.onFinished := ObjBindMethod(this, "webhookRes")
			http.send(JSON.dump(this.getMsg(content, true)))
		}

		webhookRes(http) {
			debug.print("[Webhook] " http.status ": " http.text)
		}

		getId(str) {
			regex := regex(str, "(?<id>\d{9,})")
			return regex.id
		}

		getMsg(content, webhook := false) {
			if IsObject(content) {
				msg := content.get(webhook)
			} else {
				if StrLen(content) > 2000
					Throw Exception("Message too long", -2)
				msg := {content: content}
			}
			return msg
		}

		ISODATE(str) {
			match := regex(str, "(?<YYYY>\d{4})-?(?<MM>\d{2})-?(?<DD>\d{2})T?(?<HH>\d{2}):?(?<MI>\d{2}):?(?<SS>\d{2}(?<SD>.\d+)?)\+?(?<TZ>\d{2}:\d{2})?")
			return match.YYYY match.MM  match.DD  match.HH  match.MI  match.SS ;  match.SD
		}

		getEmoji(name, wrap := true) {
			emoji := this.api.getEmoji(name)
			wraps := (wrap ? ["<" (emoji.animated ? "a" : "") ":", ">"] : [])
			return wraps[1] name ":" emoji.id wraps[2]
		}

		sanitize(str) {
			return StrReplace(str, "``", chr(8203) "``")
		}

		codeBlock(lang, code, sanitize := true, emptymsg := "No output") {
			if (code = "" || code = "`n")
				return emptymsg
			return "``````" lang "`n" (sanitize ? this.sanitize(code) : code) "``````"
		}
	}

	CallAPI(method, endpoint, data := "", async := false) {
		static BaseURL := "https://discord.com/api/"
		http := new requests(method, BaseURL endpoint,, async)
		count := new Counter(, true)
		; ? Try the request multiple times if necessary
		Loop 2 {
			http.headers["Authorization"] := "Bot " this.token

			if data
				http.headers["Content-Type"] := "application/json"

			http.headers["User-Agent"] := "Discord.ahk"
			httpout := http.send(data ? JSON.dump(data) : "")
			debug.print(format("[{}:{}] [{}ms] {}", method, httpout.status, count.get(), endpoint))
			httpjson := httpout.json()
			; TODO: ratelimit
			; this.ratelimit.bucket := httpout.headers["x-ratelimit-bucket"]
			; this.ratelimit.limit := httpout.headers["x-ratelimit-limit"]
			; this.ratelimit.remaining := httpout.headers["x-ratelimit-remaining"]
			; this.ratelimit.reset := httpout.headers["x-ratelimit-reset"]
			; this.ratelimit["reset-after"] := httpout.headers["x-ratelimit-reset-after"]
			; debug.print(this.ratelimit)

			; * Handle rate limiting
			if (httpout.status = 429) {
				if !httpjson.retry_after
					break

				sleep % httpjson.retry_after
				continue
			}
			break
		}

		; * Request was unsuccessful
		if (httpout.status != 200 && httpout.status != 204) {
			debug.print("Request failed: " httpout.text)
			throw Exception(httpjson.message, -2, httpjson.code)
		}
		return httpjson
	}

	; ? Sends data through the websocket
	Send(Data) {
		this.ws.send(JSON.dump(Data))
	}

	SetPresence(status, playing := "", type := 0) {
		activity := []
		if playing
			activity.push({name: playing, type: type})
		this.Send({op: 3, d: {since: "null", activities: activity, status: status, afk: false}})
	}

	SendMessage(channel, content) {
		msg := this.utils.getMsg(content)
		if (StrLen(msg.content) > 2000)
			Throw Exception("Message too long", -1)
		return this.CallAPI("POST", "channels/" channel "/messages", msg)
	}

	getChannel(guild, channel) {
		return this.cache.channelGet(guild, channel)
	}

	GetMessages(channel, opt) {
		return this.CallAPI("GET", "channels/" channel "/messages?" requests.encode(opt))
	}

	GetMessage(channel, id) {
		if !this.cache.messageGet(channel, id)
			this.cache.messageSet(channel, this.CallAPI("GET", "channels/" channel "/messages/" id))
		return new discord.message(this, this.cache.messageGet(channel, id))
	}

	getUser(id) {
		; if !this.cache.userGet(id)
			; this.cache.userSet(id, this.CallAPI("GET", "users/" id))
			; Throw Exception("No user found with id " id, -2)
		return this.cache.userGet(id)
	}

	EditMessage(channel, id, content) {
		msg := this.utils.getMsg(content)
		return this.CallAPI("PATCH", "channels/" channel "/messages/" id, msg)
	}

	AddBan(guild, user, reason, delet) {
		return this.CallAPI("PUT", "guilds/" guild "/bans/" user, {reason: reason, delete_message_days: delet})
	}

	RemoveBan(guild, user) {
		return this.CallAPI("DELETE", "guilds/" guild "/bans/" user)
	}

	AddReaction(channel, id, emote) {
		if RegExMatch(emote, "^[\w#@$\?\[\]\x80-\xFF]+$")
			emote := this.utils.getEmoji(emote, false)
		return this.CallAPI("PUT", "channels/" channel "/messages/" id "/reactions/" urlEncode(emote) "/@me")
	}

	RemoveReaction(channel, id, emote) {
		if RegExMatch(emote, "^[\w#@$\?\[\]\x80-\xFF]+$")
			emote := this.utils.getEmoji(emote, false)
		return this.CallAPI("DELETE", "channels/" channel "/messages/" id "/reactions/" urlEncode(emote) "/@me")
	}

	TypingIndicator(channel) {
		return this.CallAPI("POST", "channels/" channel "/typing")
	}

	BulkDelete(channel, messages) {
		return this.CallAPI("POST", "channels/" channel "/messages/bulk-delete", {messages: messages})
	}

	DeleteMessage(channel, message) {
		return this.CallAPI("DELETE", "channels/" channel "/messages/" message)
	}

	LeaveGuild(guild) {
		if !this.cache.guildGet(guild)
			Throw Exception("Im not on guild " guild, -1)
		return this.CallAPI("DELETE", "users/@me/guilds/" guild)
	}

	changeSelfNick(guild, nick) {
		this.CallAPI("PATCH", "guilds/" guild "/members/@me/nick", {nick: nick})
	}

	createDM(id) {
		if !this.cache.dmGet(id)
			this.cache.dmSet(id, this.CallAPI("POST", "users/@me/channels", {recipient_id: id}))
		return this.cache.dmGet(id)
	}

	getEmoji(name, guild := "") {
		if !guild
			guild := this.owner.guild
		return this.cache.emojiGet(guild, name)
	}

	getMember(guild, id) {
		if !this.cache.memberGet(guild, id)
			this.cache.memberSet(guild, this.CallAPI("GET", "guilds/" guild "/members/" id))
		return this.cache.guildGet(guild).members[this.cache.memberGet(guild, id)]
	}

	SendHeartbeat() {
		if !this.connected
			return
		if !this.HeartbeatACK {
			this.reconnect(true)
			return
		}

		this.HeartbeatACK := False
		this.Send({op: 1, d: this.Seq})
	}

	identify() {
		data := this.Send({
		(Join
			op: 2,
			d: {
				token: this.token,
				properties: {
					"$os": "windows",
					"$browser": "Discord.ahk",
					"$device": "Discord.ahk"
				},
				presence: {
					activity: [{
						name: "Starting..",
						type: 0
					}],
					status: "dnd",
					afk: false
				},
				intents: this.intents,
				compress: true,
				large_threshold: 250
			}
		)})
	}

	resume() {
		debug.print("[Reconnect] Trying to resume with session")
		res := this.resumedata
		this.Send({op: 6, d: {token: this.token, session_id: res.session, seq: res.seq}})
		this.resumedata := ""
	}

	/*
		? OP HANDLING
	*/

	OP_HELLO(Data) {
		this.HeartbeatACK := True
		Interval := Data.d.heartbeat_interval
		fn := ObjBindMethod(this, "SendHeartbeat")
		SetTimer %fn%, % Interval
		TimeOnce(ObjBindMethod(this, this.resumedata ? "resume" : "identify"), 50)
		this.connected := true
	}

	OP_HEARTBEATACK(Data) {
		this.HeartbeatACK := True
	}

	OP_INVALIDSESSION(Data) {
		Debug.print("[SESSION] Attempting to identify to discord api")
		TimeOnce(ObjBindMethod(this, "identify"), random(1000, 4000))
	}

	OP_Dispatch(Data) {
		switch data.t {
			case "MESSAGE_CREATE":
				this.cache.messageSet(data.d.channel_id, data.d)
				if data.d.author.id = this.self.id
					return ;; ? Ignore own messages

				Data.d := new this.message(this, Data.d)
			case "MESSAGE_REACTION_ADD":
				if data.d.user_id == this.self.user_id
					return
				data.d := new this.reaction(this, data.d)

			case "READY":
				this.session_id := Data.d.session_id
				this.self := data.d.user
				return

			case "GUILD_CREATE":
				this.cache.guildSet(data.d.id, data.d)
				if (data.d.id = this.owner.guild) {
					TimeOnce(ObjBindMethod(this, "dispatch", "READY", data.d), 0)
					debug.print("[DISCORD] READY")
				}
			case "GUILD_UPDATE":
				this.cache.guildUpdate(data.d.guild_id, data.d)
			case "GUILD_DELETE":
				if !data.d.unavailable
					this.cache.guildDelete(data.d.id)
			case "GUILD_EMOJIS_UPDATE": ;;UNCHECKED
				this.cache.emojiUpdate(data.d.guild_id, data.d.emojis)

			case "GUILD_ROLE_CREATE":
				this.cache.roleCreate(data.d.guild_id, data.d.role)
			case "GUILD_ROLE_UPDATE":
				this.cache.roleUpdate(data.d.guild_id, data.d.role.id, data.d.role)
			case "GUILD_ROLE_DELETE":
				this.cache.roleDelete(data.d.guild_id, data.d.role_id)

			case "GUILD_MEMBER_UPDATE":
				this.cache.memberUpdate(data.d.guild_id, data.d.user.id, data.d)
			case "GUILD_MEMBER_REMOVE":
				this.cache.memberDelete(data.d.guild_id, data.d.user.id)
			case "GUILD_MEMBER_ADD":
				this.cache.memberSet(data.d.guild_id, data.d.user)

			case "CHANNEL_UPDATE":
				this.cache.channelUpdate(data.d.guild_id, data.d.id, data.d)
			case "CHANNEL_CREATE":
				this.cache.channelSet(data.d.guild_id, data.d)
			case "CHANNEL_DELETE":
				this.cache.channelDelete(data.d.guild_id, data.d.id)
		}

		this.dispatch(data.t, data.d)
	}

	dispatch(event, data) {
		fn := this.creator["_event"]
		%fn%(this.creator, event, data)
	}

	/*
		? Websocket
	*/

	OnMessage(Event) {
		Data := JSON.load(Event.data)

		; * Save the most recent sequence number for heartbeats
		if Data.s
			this.Seq := Data.s

		opname := this.OPCode[data.op]

		if (opname != "dispatch")
			debug.print("|" opname)
		this["OP_" opname](Data)
	}

	OnError(reason := "", code := "", message := "") {
		; TODO FIX:
		debug.print(format("Error, {},: {} {}", code, reason, message))
		this.reconnect(true)
	}


	OnClose(reason := "", code := "") {
		static allowed := [1000, 1001, 4000, 4007, 4009]
		debug.print(format("[DISCORD] Closed, {}: {}", code, reason))
		if !contains(code, allowed)
			Throw Exception("Code not allowed")
		this.reconnect(true)
	}


	/*
		? Constructors
	*/

	class paginator {
		__New(content, limit := 1950) {
			content := discord.utils.sanitize(content)
			this.pages := []
			lines := StrSplit(content, "`n", "`r")
			temp := ""
			for _, value in lines {
				if StrLen(temp value) > limit {
					this.pages.push(temp)
					temp := ""
				}
				temp .= value "`n"
			}
			this.pages.push(temp)
		}
	}

	class embed {
		__New(title := "", content := "", color := "0x159af3") {
			if StrLen(title) > 256
				Throw Exception("Embed title too long", -1)
			if StrLen(content) > 2048
				Throw Exception("Embed description too long", -1)

			this.embed := {title: title
				,description: content
				,color: format("{:u}", color)
				,fields: []}
		}

		setContent(byref str) {
			if StrLen(str) > 1990
				Throw Exception("Content too long", -1)
			if StrLen(Str) == 0
				return
			this.content := str
		}

		setUrl(url) {
			this.embed.url := url
		}

		setAuthor(name, icon_url := "") {
			if StrLen(name) > 256
				Throw Exception("Author name too long", -1)
			this.embed.author := {name: name, icon_url: icon_url}
		}

		setFooter(text, icon_url := "") {
			if StrLen(text) > 2048
				Throw Exception("Footer text too long", -1)
			this.embed.footer := {text: text, icon_url: icon_url}
		}

		setTimestamp(time) {
			this.embed.timestamp := time
		}

		setImage(img) {
			this.embed.image := {url: img}
		}

		setThumbnail(img) {
			this.embed.thumbnail := {url: img}
		}

		addField(title, content, inline := false, empty := false) {
			if StrLen(title) > 256
				Throw Exception("Field title too long", -1)
			if StrLen(content) > 1024
				Throw Exception("Field content too long", -1)

			if empty
				content := title := chr(8203)

			if (StrLen(content) == 0 || StrLen(title) == 0)
				return

			this.embed.fields.push({name: title, value: content, inline: inline})
		}

		get(webhook := false) {
			if (webhook)
				return {content: this.content, embeds: [this.embed]}
			return {content: this.content, embed: this.embed}
		}
	}

	class author {
		static permissionlist := {ADD_REACTIONS: 0x00000040, ADMINISTRATOR: 0x00000008, ATTACH_FILES: 0x00008000, BAN_MEMBERS: 0x00000004, CHANGE_NICKNAME: 0x04000000, CONNECT: 0x00100000, CREATE_INSTANT_INVITE: 0x00000001, DEAFEN_MEMBERS: 0x00800000, EMBED_LINKS: 0x00004000, KICK_MEMBERS: 0x00000002, MANAGE_CHANNELS: 0x00000010, MANAGE_EMOJIS: 0x40000000, MANAGE_GUILD: 0x00000020, MANAGE_MESSAGES: 0x00002000, MANAGE_NICKNAMES: 0x08000000, MANAGE_ROLES: 0x10000000, MANAGE_WEBHOOKS: 0x20000000, MENTION_EVERYONE: 0x00020000, MOVE_MEMBERS: 0x01000000, MUTE_MEMBERS: 0x00400000, PRIORITY_SPEAKER: 0x00000100, READ_MESSAGE_HISTORY: 0x00010000, SEND_MESSAGES: 0x00000800, SEND_TTS_MESSAGES: 0x00001000, SPEAK: 0x00200000, STREAM: 0x00000200, USE_EXTERNAL_EMOJIS: 0x00040000, USE_VAD: 0x02000000, VIEW_AUDIT_LOG: 0x00000080, VIEW_CHANNEL: 0x00000400, VIEW_GUILD_INSIGHTS: 0x00080000}

		__New(api, data, guild := "", channel := "") {
			static avatar := "https://cdn.discordapp.com/avatars/{}/{}.webp?size=1024"
			this.api := api
			this.data := data
			this.id := data.id
			this.bot := data.bot
			this.name := data.username
			this.guild := guild
			this.channel := channel
			this.discriminator := data.discriminator
			this.mention := "<@" data.id ">"
			this.avatar := format(avatar, this.id, data.avatar)
			this.permissions := []
			this.isGuildOwner := (this.id = guild.owner)
			this.isBotOwner := (this.id = api.owner.id)
			if !guild {
				try {
					throw Exception("", -2)
				} catch e {
					debug.print(JSON.dump(e) " did not provide a guild")
				}
			}
			if guild {
				member := api.getMember(guild.id, this.id)
				this.roles := member.roles

				perms := allow := deny := 0
				for _, value in this.roles {
					index := api.cache.roleGet(guild.id, value)
					role := api.cache.guildGet(guild.id).roles[index]
					perms |= role.permissions
				}
				if (this.checkFlag(perms, this.permissionlist["ADMINISTRATOR"]) || this.isGuildOwner) {
					for key, _ in this.permissionlist {
						this.permissions.push(key)
					}
					return this
				}
				for _, value in this.roles {
					overwrite := channel.getOverwrite(value)
					if overwrite {
						allow |= overwrite.allow
						deny |= overwrite.deny
					}
				}
				perms &= ~deny
				perms |= allow
				for key, flag in this.permissionlist {
					if this.checkFlag(perms, flag)
						this.permissions.push(key)
				}
			}
		}

		sendDM(content) {
			channel := this.api.createDM(this.id)
			this.api.SendMessage(channel.id, content)
		}

		get(userid) {
			return new discord.author(this.api, this.api.getUser(userid), this.guild, this.channel)
		}

		notMention() {
			return this.name "@" this.discriminator
		}

		checkFlag(perms, flag) {
			return (perms & flag) == flag
		}
	}

	class guild {
		__New(api, id) {
			this.api := api
			this.data := api.cache.guildGet(id)
			this.name := this.data.name
			this.id := this.data.id
			this.owner := this.data.owner_id
			this.region := this.data.region
		}
	}

	class reaction {
		__New(api, data) {
			this.api := api
			this.data := data
			this.guild := new discord.guild(api, data.guild_id)
			this.author := new discord.author(api, data.member.user, this.guild)
			this.message := data.message_id
			this.channel := data.channel_id
			this.emoji := data.emoji.name
		}
	}

	class channel {
		__New(api, channel, guild := "") {
			this.api := api
			if guild {
				index := api.getChannel(guild.id, channel)
				this.data := guild.data.channels[index]
				this.overwrites := this.data.permission_overwrites
				this.nsfw := this.data.nsfw
				this.guild := 1
			}
			this.id := channel
		}

		getOverwrite(id) {
			if !this.guild
				Throw Exception("No guild provided on channel", -1)

			for _, value in this.overwrites {
				if (value.id = id)
					return value
			}
		}
	}

	class message {
		__New(api, data) {
			this.data := data
			this.id := data.id
			this.api := api
			this.message := data.content
			if data.guild_id {
				this.guild := new discord.guild(api, data.guild_id)
			}
			this.channel := new discord.channel(api, data.channel_id, this.guild)
			if !data.webhook_id {
				this.self := new discord.author(api, api.self, this.guild, this.channel)
				this.author := new discord.author(api, data.author, this.guild, this.channel)
				if data.referenced_message {
					data.referenced_message.guild_id := data.guild_id
					this.referenced_msg := new api.message(api, data.referenced_message)
				}
			}
		}

		typing() {
			this.api.TypingIndicator(this.channel.id)
		}

		react(reaction) {
			this.api.AddReaction(this.channel.id, this.id, reaction)
		}

		reply(data) {
			msg := this.api.SendMessage(this.channel.id, data)
			msg.guild_id := this.guild.id
			return new this.api.message(this.api, msg)
		}

		edit(data) {
			this.api.EditMessage(this.channel.id, this.data.id, data)
		}

		delete() {
			this.api.DeleteMessage(this.channel.id, this.data.id)
		}

		getEmoji(name) {
			return this.api.utils.getEmoji(name)
		}
	}
}
