#import "Curl";
#import "Basic";
#import "String";

Rest_Method :: enum {
    GET;
    POST;
    PUT;
    DELETE;
}

request :: ($method: Rest_Method, url: string, extra_headers : []string = .[], data := "") -> bool, string {
    // Init Curl and setup a deferred cleanup
    curl := curl_easy_init();
    if !curl {
+       print("An error occured while initting up the curl connection, but Curl doesn't tell us why.\n");
        return false, "";
    }
    defer curl_easy_cleanup(curl);

    // Init string builder, so we can output a generic string
    builder: String_Builder;
    builder.allocator = temp; // We are not planning to keep the string long term, so we will use temp allocator, in a real application that decision has to be made for yourself

    curl_easy_setopt(curl, .WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, .WRITEDATA, *builder);
    curl_easy_setopt(curl, .SSL_OPTIONS, CURLSSLOPT_NATIVE_CA);
    header_list : *curl_slist = null;
    defer curl_slist_free_all(header_list);
    for h : extra_headers {
        print("Extra header:\n%\n", h);
        header_list = curl_slist_append(header_list, h.data);
    }
    if extra_headers.count > 0 {
        curl_easy_setopt(curl, .HTTPHEADER, header_list);
    }
    // Set target URL
    #if method == .GET {
        // Add request data to the url, since GET requests expect it there
        // Maybe this shouldn't be included in the example, for the sake of reducing complexity (mandate that data is passed in the url for the get request)
        url_builder: String_Builder;

        append(*url_builder, url);
        if !ends_with(url, "/") && !ends_with(url, "\\") {
            append(*url_builder, "/");
        }
        append(*url_builder, "?");
        append(*url_builder, data);

        // Ideally we would only do one temp allocation here, something like builder_to_cstring
        curl_easy_setopt(curl, .URL, temp_c_string(builder_to_string(*url_builder,, temp)));
    } else {
        curl_easy_setopt(curl, .URL, temp_c_string(url));
    }

    // Pass request data
    #if method == .GET {
        // Already set up in the URL!
    } else if method == .POST {
        curl_easy_setopt(curl, .POST, 1);
        if data  curl_easy_setopt(curl, .POSTFIELDS, temp_c_string(data));
    } else if method == .PUT {
        curl_easy_setopt(curl, .CUSTOMREQUEST, "PUT");
        if data  curl_easy_setopt(curl, .POSTFIELDS, temp_c_string(data));
    } else if method == .DELETE {
        curl_easy_setopt(curl, .CUSTOMREQUEST, "DELETE");
        if data  curl_easy_setopt(curl, .POSTFIELDS, temp_c_string(data));
    }

    // Perform the "easy" action
    error_code := curl_easy_perform(curl);
    if error_code != .OK {
        error_message := to_string(curl_easy_strerror(error_code));
        defer free(error_message);
        print("Curl Error: %\n", error_message);
        return false, "";
    }

    // In a real application you would most likely use default allocator,
    // here we only intend to use the string short term
    return true, builder_to_string(*builder,, temp);
}

// Curl expects a C function, that's why we have to use #c_call, and since #c_call doesn't provide a context and JAI function need it, we push_context
write_callback :: (contents: *u8, count: u64, size: u64, builder: *String_Builder) -> u64 #c_call {
    total_size := count * size;
    new_context: Context;
    push_context new_context {
        // Append to the builder
        append(builder, contents, cast(s64) total_size);
    }
    return total_size;
}
