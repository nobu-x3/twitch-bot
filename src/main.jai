#load "client.jai";

UPTIME_CHECK_INTERVAL_SEC :: 300;


main :: () {
    res, env_vars := parse_env("env");
    defer deinit(*env_vars);
    client, success := client_init(*env_vars);
    defer client_deinit(*client);
    if !success {
        log("Failed to initialize");
        exit(1);
    }
    // success = client_set_poll_handle(*client);
    last_uptime_check := current_time_monotonic();
    while true {
        if to_seconds(current_time_monotonic() - last_uptime_check) > UPTIME_CHECK_INTERVAL_SEC {
            delta_time := current_time_monotonic() - last_uptime_check;
            client.token.expires_in -= cast(u64) to_seconds(delta_time);
            last_uptime_check = current_time_monotonic();
            if client.token.expires_in <= 0 {
                refresh_result := client_refresh_token(*client);
                log("Failed to refresh token");
                if !refresh_result break;
            }
        }
        password := tprint("oauth:%", client.token.access_token);
        if (client.status & .Connected) == 0 {
            client_connect(*client, client.login_data.username, password);
        }
        success = client_update(*client, 50000);
        if !success break;
        reset_temporary_storage();
    }
}
