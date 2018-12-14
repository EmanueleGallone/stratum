"""P4c configuration generation rules."""

load("//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

# Runs the p4c binary with the Hercules backend on the P4_16 sources. The P4_16
# code should be targeted to the v1model in p4lang_p4c/p4include.
def _generate_p4c_hercules_config(ctx):
    """Preprocesses P4 sources and runs Hercules p4c on pre-processed P4 file."""

    # Preprocess all files and create 'p4_preprocessed_file'
    p4_preprocessed_file = ctx.new_file(
        ctx.configuration.genfiles_dir,
        ctx.label.name + ".pp.p4",
    )
    hdr_include_str = ""
    for hdr in ctx.files.hdrs:
        hdr_include_str += "-I " + hdr.dirname
    cpp_toolchain = find_cpp_toolchain(ctx)

    ctx.action(
        arguments = [
            "-E",
            "-x",
            "c",
            ctx.file.src.path,
            "-I.",
            "-I",
            ctx.file._model.dirname,
            "-I",
            ctx.file._core.dirname,
            hdr_include_str,
            "-o",
            p4_preprocessed_file.path,
        ] + ctx.attr.copts,
        inputs = ([ctx.file.src] + ctx.files.hdrs + [ctx.file._model] +
                  [ctx.file._core] + ctx.files.cpp),
        outputs = [p4_preprocessed_file],
        progress_message = "Preprocessing...",
        executable = cpp_toolchain.compiler_executable,
    )

    # Run Hercules p4c on pre-processed P4_16 sources to obtain the P4 info and
    # P4 pipeline config files for Hercules switches.
    gen_files = [
        ctx.outputs.out_p4_pipeline_binary,
        ctx.outputs.out_p4_pipeline_text,
        ctx.outputs.out_p4_info,
    ]

    # This string specifies the open source p4c frontend and midend options,
    # which go into the Hercules p4c --p4c_fe_options flag.
    p4c_native_options = "--nocpp " + p4_preprocessed_file.path

    annotation_map_files = ""
    for map_file in ctx.files.annotation_maps:
        if annotation_map_files:
            annotation_map_files += ","
        annotation_map_files += map_file.path

    ctx.action(
        arguments = [
            "--p4c_fe_options=" + p4c_native_options,
            "--p4_info_file=" + gen_files[2].path,
            "--p4_pipeline_config_binary_file=" + gen_files[0].path,
            "--p4_pipeline_config_text_file=" + gen_files[1].path,
            "--p4c_annotation_map_files=" + annotation_map_files,
            "--slice_map_file=" + ctx.file.slice_map.path,
            "--target_parser_map_file=" + ctx.file.parser_map.path,
        ],
        inputs = ([p4_preprocessed_file] + [ctx.file.parser_map] +
                  [ctx.file.slice_map] + ctx.files.annotation_maps),
        # Disable ASAN check, because P4C is known to leak memory b/63128624.
        env = {"ASAN_OPTIONS": "halt_on_error=0:detect_leaks=0"},
        outputs = gen_files,
        progress_message = "Compiling P4 sources to generate Hercules P4 config",
        executable = ctx.executable._p4c_hercules_binary,
    )

    return struct(files = depset(gen_files))

# Compiles P4_16 source into P4 info and P4 pipeline config files.  The
# output file names are <name>_p4_info.pb.txt and <name>_p4_pipeline.pb.txt
# in the appropriate path under the genfiles directory.
p4_hercules_config = rule(
    implementation = _generate_p4c_hercules_config,
    fragments = ["cpp"],
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True),
        "hdrs": attr.label_list(
            allow_files = True,
            mandatory = True,
        ),
        "out_p4_info": attr.output(mandatory = True),
        "out_p4_pipeline_binary": attr.output(mandatory = True),
        "out_p4_pipeline_text": attr.output(mandatory = True),
        "annotation_maps": attr.label_list(
            allow_files = True,
            mandatory = False,
            default = [
                Label("//platforms/networking/hercules/p4c_backend/switch:annotation_map_files"),
            ],
        ),
        "parser_map": attr.label(
            allow_single_file = True,
            mandatory = False,
            default = Label("//platforms/networking/hercules/p4c_backend/switch:parser_map_files"),
        ),
        "slice_map": attr.label(
            allow_single_file = True,
            mandatory = False,
            default = Label("//platforms/networking/hercules/p4c_backend/switch:slice_map_files"),
        ),
        "copts": attr.string_list(),
        "_model": attr.label(
            allow_single_file = True,
            mandatory = False,
            default = Label("//p4lang_p4c:p4include/v1model.p4"),
        ),
        "_core": attr.label(
            allow_single_file = True,
            mandatory = False,
            default = Label("//p4lang_p4c:p4include/core.p4"),
        ),
        "_p4c_hercules_binary": attr.label(
            cfg = "host",
            executable = True,
            default = Label("//platforms/networking/hercules/p4c_backend/switch:p4c_herc_switch"),
        ),
        "cpp": attr.label_list(default = [Label("//tools/cpp:crosstool")]),
        "_cc_toolchain": attr.label(
            default = Label("//tools/cpp:current_cc_toolchain"),
        ),
    },
)
