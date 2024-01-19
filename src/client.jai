#import "jaison";
#import "Basic";
#import "File";
#import "rest";
#import "String";
#import "Hash_Table";
#import "Socket";

Token :: struct {
    access_token: string;
    expires_in: u64;
    bearer: string;
}

Client :: struct {
    client_id : string;
    token : Token;
    chat_socket: Socket;
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

client_call :: (client: *Client){
    print("%\n", client.token.access_token);
    result, response := request(.GET, "https://api.twitch.tv/helix/users?login=nobu_x3",
    .[tprint("Authorization: Bearer %", client.token.access_token), tprint("Client-Id: %", client.client_id)]
    );
    print("%\n", response);
}

client_init :: () -> Client #must {
    res, env_vars := parse_env("env");
    defer deinit(*env_vars);
    client_id, cid_res := table_find(*env_vars, "CLIENTID");
    secret, secret_res := table_find(*env_vars, "CLIENTSECRET");
    resp_string := tprint("client_id=%&client_secret=%&grant_type=client_credentials", client_id, secret);
    result, response := request(.POST, "https://id.twitch.tv/oauth2/token", .[], resp_string);
    client : Client;
    // data := cast(*u8) alloc(client_id.count);
    // memcpy(data, client_id.data, client_id.ount);
    // client.client_id.data = data;
    // client.client_id.count = client_id.count;
    client.client_id = client_id;
    res, client.token = json_parse_string(response, Token);
    res = socket_init();
    serv : sockaddr_in; // main socket variable
    serv.sin_family = AF_INET;
    serv.sin_port = htons(3000);
    c_serv_addr := to_c_string("http://localhost");
    defer free(c_serv_addr);
	addr := inet_addr(c_serv_addr);
    #if OS == .WINDOWS {
        serv.sin_addr.S_un.S_addr = addr;
    } else {
        serv.sin_addr.s_addr  = addr;
    }
    client.chat_socket = socket(AF_INET, .SOCK_STREAM, 0);
    bind(client.chat_socket, "http://localhost", 3000);
    print("socket: %\n", client.chat_socket);
    // sres := bind(client.chat_socket, "rc://irc.chat.twitch.tv", 6667);
    server_address: sockaddr_in;
    server_address.sin_family = AF_INET;
    c_address := to_c_string("rc://irc.chat.twitch.tv");
    defer free(c_address);
	addr = inet_addr(c_address);
    #if OS == .WINDOWS {
        server_address.sin_addr.S_un.S_addr = addr;
    } else {
        server_address.sin_addr.s_addr = addr;
    }
    server_address.sin_port = htons(6667);
    sres := inet_pton(client.chat_socket, "127.0.0.1", *server_address.sin_addr);
    conn_res := connect(client.chat_socket, cast(*sockaddr)*server_address, size_of(sockaddr_in));
    print("conn res : %\n", conn_res);
    if conn_res == -1 {
        print("conn err: %\n", get_last_socket_error());
    }
    return client;
}
