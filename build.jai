#import "File";
#import "File_Utilities";

build :: (){
    make_directory_if_it_does_not_exist("bin");
    {
        w := compiler_create_workspace("Twitch Bot");
        if !w {
            print("Workspace creation failed.\n");
            return;
        }
        import_path: [..] string;
        options := get_build_options();
        set_optimization(*options, .DEBUG);
        array_add(*import_path, .. options.import_path);
        array_add(*import_path, "./modules");
        options.import_path = import_path;
        options.output_path = "./bin/";
        options.output_executable_name = "twitch-bot";
        set_build_options(options, w);
        compiler_begin_intercept(w);
        add_build_file("./src/main.jai", w);
        compiler_end_intercept(w);
    }
    set_build_options_dc(.{do_output=false});
}

#run build();

#import "Basic";
#import "Compiler";
#import "File";
