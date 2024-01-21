#load "client.jai";

UPTIME_CHECK_INTERVAL_SEC :: 10;

main :: () {
    res, env_vars := parse_env("env");
    defer deinit(*env_vars);
    client, success := client_init(*env_vars);
    defer client_deinit(*client);
    if !success {
        log("Failed to initialize");
        exit(1);
    }
    success = client_set_poll_handle(*client);
    last_uptime_check := current_time_monotonic();
    while true {
        if to_seconds(current_time_monotonic() - last_uptime_check) > UPTIME_CHECK_INTERVAL_SEC {
            client.token = client_get_access_token(*env_vars);
        }
        password := tprint("oauth:%", client.token.access_token);
        if (client.status & .Connected) == 0 {
            client_connect(*client, client.login_data.username, password);
        }
        success = client_update(*client);
        if !success break;
        reset_temporary_storage();
    }
}
