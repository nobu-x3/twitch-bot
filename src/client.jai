#import "jaison";
#import "Basic";
#import "File";
#import "rest";
#import "String";
#import "Hash_Table";
#import "Socket";
#import "System";
#import "POSIX";

#load "commands.jai";

Token :: struct {
    access_token : string;
    expires_in : u64;
    refresh_token : string;
    scope : []string;
    token_type : string;
}

Status :: enum {
    Disconnected :: 0;
    Connecting :: 1;
    Connected :: 2;
    Authing :: 4;
    Authed :: 8;
}

Client :: struct {
    client_id : string;
    secret : string;
    login_data : Login_Data;
    channel : string;
    token : Token;
    socket: Socket = INVALID_SOCKET;
    buffer : []u8;
    status : Status = .Disconnected;
    unconsumed_bytes : int;
    #if OS == .LINUX {
        epoll_handle:    s32 = -1;
    }
}

Login_Data :: struct {
    username : string;
    password : string;
    display_name : string;
    id : string;
}

Event :: struct {
    prefix : string;
    command : string;
    command_args : []string;
    parameter : string;
    tags : []Tag;
    type : Command_Type;
    nickname : string;
    channel : string;
    message : string;
    ctcp : string;
}

Command_Type :: enum {
    UNKNOWN;
    AUTHENTICATED;
    GLOBALUSERSTATE;
    PRIVMSG;
    RECONNECT;
    PING;
    JOIN;
    PART;
    NOTICE;
    CLEARCHAT;
    ROOMSTATE;
    USERSTATE;
    MODERATOR;
    USERNOTICE;
    WHISPER;
    NAMES;
    END_OF_NAMES;
}


client_call :: (client: *Client){
    print("%\n", client.token.access_token);
    result, response := request(.GET, "https://api.twitch.tv/helix/users?login=nobu_x3",
    .[tprint("Authorization: Bearer %", client.token.access_token), tprint("Client-Id: %", client.client_id)]
    );
    print("%\n", response);
}

BUFFER_SIZE :: 2048;

client_init :: (env_vars : *Table(string, string)) -> Client, bool #must {
    client_id, cid_res := table_find(env_vars, "CLIENTID");
    secret, secret_res := table_find(env_vars, "CLIENTSECRET");
    nickname, nickname_res := table_find(env_vars, "USERNAME");
    channel, channel_res := table_find(env_vars, "CHANNELNAME");
    password_token, pass_res := table_find(env_vars, "PASSWORD");
    log("password_token:%\n", password_token);
    resp_string := tprint("client_id=%&client_secret=%&code=%&grant_type=authorization_code&redirect_uri=http://localhost:3000", client_id, secret, password_token);
    result, response := request(.POST, "https://id.twitch.tv/oauth2/token", .[], resp_string);
    // result, response := request(.POST, "https://id.twitch.tv/oauth2/authorize?response_type=token&client_id=%&redirect_uri=http://localhost:3000&scope=chat%3Aread", .[], client_id);
    client : Client;
    res : bool;
    log("response: %\n", response);
    res, client.token = json_parse_string(response, Token);
    client.client_id = client_id;
    client.secret = secret;
    client.channel = channel;
    res = socket_init();
    if !res return client, false;
    password := tprint("oauth:%",client.token.access_token);
    res = client_connect(*client, nickname, password);
    return client, res;
}

client_get_access_token :: (client: *Client, env_vars: *Table(string, string)) -> Token {
    password, pass_res := table_find(env_vars, "PASSWORD");
    resp_string := tprint("client_id=%&client_secret=%&code=%&grant_type=authorization_code&redirect_uri=http://localhost:3000", client.client_id, client.secret, password);
    result, response := request(.POST, "https://id.twitch.tv/oauth2/token", .[], resp_string);
    res, token := json_parse_string(response, Token);
    return token;
}

client_refresh_token :: (client: *Client) -> bool {
    resp_string := tprint("grant_type=refresh_token&refresh_token=%&client_id=%&client_secret=%", client.token.refresh_token, client.client_id, client.secret);
    result, response := request(.POST, "https://id.twitch.tv/oauth2/token", .[], resp_string);
    if !result return false;
    result, client.token = json_parse_string(response, Token);
    if !result return false;
    return true;
}

client_connect :: (client: *Client, username: string, password: string, hostname := "irc.chat.twitch.tv", port := "6667") -> bool {
    if client.buffer.data {
        array_free(client.buffer);
    }
    client.buffer = NewArray(BUFFER_SIZE, u8, initialized = false);
    client.socket = socket(AF_INET, .STREAM, .TCP);
    if client.socket == -1 {
        error_code := get_last_socket_error();
        error_string := get_error_string(error_code);
        log_error("Could not create socket: % %", error_code, error_string);
        return  false;
    }
    res : bool;
    res = set_blocking(client.socket, false);
    if !res {
        close_and_reset(*client.socket);
        return  false;
    }
    res = set_keepalive(client.socket, true, idle_seconds_before_keepalive = 10, keepalive_interval_seconds = 5, num_keepalive_attempts = 4);
    if !res {
        close_and_reset(*client.socket);
        return  false;
    }
    client_set_poll_handle(client);
    hints: addrinfo;
	hints.ai_family   = AF_INET;
	hints.ai_socktype = .STREAM;
	hints.ai_protocol = .TCP;
    c_hostname := temp_c_string(hostname);
    c_port := temp_c_string(port);
    info: *addrinfo;
    addrinfo_res := getaddrinfo(c_hostname, c_port, *hints, *info);
    if addrinfo_res {
        error_code, error_string := get_error_value_and_string();
        log_error("Could not get addr info: % %", error_code, error_string);
        disconnect(client);
		return  false;
	}
    defer freeaddrinfo(info);
    con := connect(client.socket, info.ai_addr, info.ai_addrlen);
    if con == -1 {
        error_code := errno();
        if error_code != EINPROGRESS && error_code != EALREADY {
            error_string := get_error_string(error_code);
            log_error("Could not connect to host: % %", error_code, error_string);
            disconnect(client);
            return  false;
        }
    }
    client.status = .Connecting;
    client.login_data.username = copy_string(username);
    client.login_data.password = copy_string(password);
    return true;
}


client_set_poll_handle :: (client: *Client) -> bool {
    #if OS == .LINUX {
        client.epoll_handle = epoll_create(1);
        if client.epoll_handle < 0 {
            error_code, error_string := get_error_value_and_string();
            log_error("Could not create epoll instance: % %", error_code, error_string);
            disconnect(client);
            return false;
        }
        // Set up the epoll instance
        eev: epoll_event;
        eev.data.ptr = client;
        eev.events = EPOLLRDHUP | EPOLLOUT | EPOLLIN | EPOLLET;
        result := epoll_ctl(client.epoll_handle, .ADD, client.socket, *eev);
        if result {
            error_code, error_string := get_error_value_and_string();
            log_error("Could not configure epoll instance: % %", error_code, error_string);
            disconnect(client);
            return false;
        }
    }
    return true;
}

client_update :: (client: *Client, timeout : s32 = -1) -> bool {
    #if OS == .LINUX {
        epev: epoll_event;
        sigset: sigset_t;
        sigemptyset(*sigset);
        // Signals to ignore to prevent loop from exiting. epoll_wait()
        // and epoll_pwait() will return -1 if these are caught.
        sigaddset(*sigset, SIGCHLD);  // default: ignore
        sigaddset(*sigset, SIGCONT);  // default: continue execution
        sigaddset(*sigset, SIGURG);   // default: ignore
        sigaddset(*sigset, SIGWINCH); // default: ignore
        num_events := epoll_pwait(client.epoll_handle, *epev, 1, timeout, *sigset);
        if num_events == -1 {
            error_code := get_error_value();
            if error_code == EINTR || error_code == EAGAIN {
                // Got interrupted, try again.
                return true;
            }
            return false;
        }
        if num_events == 0 {
            return true;
        }
        // data incoming
        if epev.events & EPOLLIN {
            success := read_and_process_data(client);
            if !success return false;
        }
        // ready to send data
        if epev.events & EPOLLOUT {
            if client.status & .Connecting {
                client.status = .Connected;
                cmd_req_all(client);
                auth(client);
            }
        }
        // Server closed the connection
        if epev.events & EPOLLRDHUP {
            log_error("Server closed the connection");
            disconnect(client);
            return false;
        }
        // Unexpected hangup on socket
        if epev.events & EPOLLHUP {
            log_error("Unexpected hangup on socket");
            disconnect(client);
            return false;
        }
        // Socket error
        if epev.events & EPOLLERR {
            log_error("Socket error");
            disconnect(client);
            return false;
        }
        if !socket_is_connected(client.socket) {
            log_error("Socket is no longer connected");
            return false;
        }
        return true;
    }
}

client_deinit :: (client: *Client) {
    disconnect(client);
    array_free(client.buffer);
}

client_send_message :: (client: *Client, msg: string) -> bool {
    remainder := msg;
    log("Sending message: %", msg);
    while remainder {
        result := send(client.socket, msg.data, cast(u64)msg.count, 0);
        if result == -1 {
            code, error := get_error_value_and_string();
            log_error("Could not send message: %\t% %\n", msg, code, error);
            return false;
        }
        remainder = slice(remainder, result, remainder.count - result);
    }
    return true;
}

parse_env :: (filepath : string) -> bool, Table(string, string) {
    env, res := read_entire_file(filepath);
    // defer free(env);
    env_vars : Table(string, string);
    // defer deinit(*env_vars);
    if !res {
        return false, env_vars;
    }
    split_env := split(env, "\n");
    for var : split_env {
        found, left, right := split_from_left(var, "=");
        if found {
            table_add(*env_vars, left, right);
        }
        else return false, env_vars;
    }
    return true, env_vars;
}

#scope_file

disconnect :: (client: *Client) {
    close_and_reset(*client.socket);
    //deinit(*client.login);
}

socket_is_connected :: (socket: s32) -> bool {
    err: s32;
    len := cast(u32) size_of(type_of(err));
    result := getsockopt(socket, SOL_SOCKET, SO_ERROR, *err, *len);
    if result != 0 {
		// Could not get the socket's status, invalid file descriptor?
        return false;
	}

    return err == 0;
}

read_and_process_data :: (client: *Client) -> bool {
    while true {
        bytes_received := recv(client.socket,
                            client.buffer.data + client.unconsumed_bytes,
                            cast(u64)(client.buffer.count - client.unconsumed_bytes),
                            0);
        log("bytes received:%\n", bytes_received);
        if bytes_received == -1 {
            error_code := errno();
            if error_code == EAGAIN || error_code == EWOULDBLOCK {
                // nothing to read
                break;
            }
            error_string := get_error_string(error_code);
            log_error("Could not read from socket: % %", error_code, error_string);
            if (client.status & .Connected) != 0 && !socket_is_connected(client.socket) {
                disconnect(client);
            }
            return false;
        }
        if bytes_received == 0 {
            log_error("Socket was closed by the server");
            return false;
        }
        client.unconsumed_bytes += bytes_received;
        success, bytes_consumed := process_data(client, array_view(client.buffer, 0, client.unconsumed_bytes));
        client.unconsumed_bytes -= bytes_consumed;
        for 0..client.unconsumed_bytes - 1 {
            client.buffer[it] = client.buffer[bytes_consumed + it];
        }
        if !success return false;
    }
    return true;
}

auth :: (client: *Client) -> bool {
    if !cmd_pass(client, client.login_data.password) return false;
    if !cmd_nick(client, client.login_data.username) return false;
    client.status |= .Authing;
    return true;
}

Tag :: struct {
    key : string;
    val : string;
}


process_data :: (client: *Client, buf: []u8) -> bool, int {
    bytes_consumed : int;
    remaining := cast(string)buf;
    while true {
        found: bool;
        message: string;
        event : Event;
        found, message, remaining = split_from_left(remaining, "\r\n");
        log("Processing data: %", message);
        if !found break;
        bytes_consumed += message.count + 2;
        success, tags, remainder := parse_tags(message);
        defer array_free(tags);
        if !success return false, bytes_consumed;
        event.tags = tags;
        success, event.prefix, remainder = parse_prefix(remainder);
        if !success return false, bytes_consumed;
        // commands
        event.command, event.command_args, event.parameter = parse_command(remainder);
        success = parse_ctcp(*event);
        if !success return false, bytes_consumed;
        // nickname
        nickname_found, nickname, nickname_remainder := split_from_left(event.prefix, "!");
        event.nickname = nickname;
        emit_event(client, *event);
    }
    return true, bytes_consumed;
}

parse_command :: (msg: string) -> string, []string, string {
    found, command_string, after  := split_from_left(msg, ":");
    cmd_found, cmd, remainder := split_from_left(command_string, " ");
    remainder = trim(remainder);
    return cmd, split(remainder, " "), after;
}

parse_ctcp :: (event: *Event) -> success: bool {
    parameter := event.parameter;
    if !parameter    return true;
	// First or last char not 0x01? Not CTCP!
    if parameter[0] != 0x01  return true;
    if parameter[parameter.count - 1] != 0x01  return true;
    found, ctcp, remainder := split_from_left(parameter, " ");
    if !found   return false;
    event.ctcp = ctcp;
    event.parameter = remainder;
    return true;
}

parse_prefix :: (msg: string) -> bool, string, string {
    if !msg.count || msg[0] != #char ":" return true, "", msg;
    found, prefix, remainder := split_from_left(msg, " ");
    if !found return false, "", msg;
    return true, prefix, remainder;
}

parse_tags :: (msg: string) -> bool, []Tag, string {
    if !msg.count || msg[0] != #char "@" return true, .[], msg;
    found, tags_str, remaining := split_from_left(msg, " ");
    if !found return false, .[], msg;
    advance(*tags_str);
    tags : [..]Tag;
    remainder := tags_str;
    while remainder {
        found, tag_str, right := split_from_left(remainder, ";");
        if !found {
            tag_str = remainder;
        }
        tag := parse_tag(tag_str);
        array_add(*tags, tag);
        remainder = right;
    }
    return true, tags, remaining;
}

emit_event :: (client: *Client, event: *Event) {
    if event.command == {
        case "001";
            client.status |= .Authed;
            event.type = .AUTHENTICATED;
        case "GLOBALUSERSTATE";
            client.status |= .Authed;
            client.login_data.display_name = copy_string(get_value(event.tags, "display-name"));
            event.type = .GLOBALUSERSTATE;
        case "JOIN";
            channel_command(event, .JOIN);
        case "PART";
            channel_command(event, .PART);
        case "CLEARCHAT";
            channel_command(event, .CLEARCHAT);
        case "ROOMSTATE";
            channel_command(event, .ROOMSTATE);
        case "USERSTATE";
            channel_command(event, .USERSTATE);
        case "MODE";
            channel_command(event, .MODERATOR);
        case "NOTICE";
            channel_command(event, .NOTICE);
            if event.parameter {
                event.message = event.parameter;
            }
        case "USERNOTICE";
            channel_command(event, .USERNOTICE);
            if event.parameter {
                event.message = event.parameter;
            }
        case "WHISPER";
            channel_command(event, .WHISPER);
            if event.parameter {
                event.message = event.parameter;
            }
        case "PING";
            event.type = .PING;
            cmd_pong(client, ifx event.command_args.count then event.command_args[0] else "");
        case "353";
            // > :<user>.tmi.twitch.tv 353 <user> = #<channel> :<user> <user2> <user3>
            // > :<user>.tmi.twitch.tv 353 <user> = #<channel> :<user4> <user5> ... <userN>
            event.type = .NAMES;
            if event.command_args.count > 2 {
                event.channel = event.command_args[2];
            }
        case "366";
            // > :<user>.tmi.twitch.tv 366 <user> #<channel> :End of /NAMES list
            event.type = .END_OF_NAMES;
            if event.command_args.count > 1 {
                event.channel = event.command_args[1];
            }
        case "RECONNECT";
            event.type = .RECONNECT;
        case "PRIVMSG";
            event.type = .PRIVMSG;
            if event.command_args.count {
                event.channel = event.command_args[0];
            }
            if event.parameter {
                event.message = event.parameter;
            }
        case;
            event.type = .UNKNOWN;
    }
    handle_event(client, event);
}

channel_command :: (event: *Event, type: Command_Type){
    event.type = type;
    if event.command_args.count {
        event.channel = event.command_args[0];
    }
}

WORKING_DIR :: #run get_working_directory();

handle_event :: (client: *Client, event: *Event) {
    if event.type == {
        case .GLOBALUSERSTATE;
            success := cmd_join(client, client.channel);
            if !success {
                log_error("Couldn’t join channel %", event.channel);
                exit(1);
            }
        case .PRIVMSG;
            user := get_value(event.tags, "display-name");
            message := event.message;
            piper_cmd := tprint("echo '% says: %' | exec %/bin/piper --model %/bin/en_US-lessac-medium.onnx --output-raw | aplay -r 22050 -f S16_LE -t raw -", user, message, WORKING_DIR, WORKING_DIR);
            log("Chat message from %: %", user, message);
            system(to_c_string(piper_cmd));
    }
}

get_value :: (tags : []Tag, key : string) -> string {
    for tags {
        if it.key == key {
            return it.val;
        }
    }
    return "";
}

parse_tag :: (str : string) -> Tag {
    tag: Tag;
    found, key, val := split_from_left(str, "=");
    tag.key = key;
    if found {
        tag.val = val;
        unescape(*tag.val);
    }
    return tag;
}

unescape :: (value_pointer: *string) {
    value := value_pointer.*;
    dest := 0;
    for i: 0..value.count - 1 {
        if value[i] == #char "\\" && i != value.count - 1 {
            i += 1;
            if value[i] == {
                case #char ":";  value[dest] = #char ";";
                case #char "s";  value[dest] = #char " ";
                case #char "\\"; value[dest] = #char "\\";
                case #char "r";  value[dest] = #char "\r";
                case #char "n";  value[dest] = #char "\n";
                case;            value[dest] = value[i];
            }
        } else {
            value[dest] = value[i];
        }
        dest += 1;
    }
    value_pointer.count = dest;
}
