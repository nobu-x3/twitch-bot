#load "client.jai";

main :: () {
    client, success := client_init();
    defer client_deinit(*client);
    success = client_set_poll_handle(*client);
}
