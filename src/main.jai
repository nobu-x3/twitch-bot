#import "Basic";
#import "rest";

main :: () {
    result, response := request(.GET, "https://twitch.tv/");
    print("result %, response %", result, response);
}
