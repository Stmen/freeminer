#!/usr/bin/perl

# install:
# sudo apt-get install valgrind clang
# sudo apt-get install google-perftools libgoogle-perftools-dev

our $help = qq{
$0 [--this_script_params] [-freeminer_params] [cmd]

#simple task
$0 valgrind_massif

# run one task with headless config
$0 --options_add=headless gdb

# pass options to app
$0 -num_emerge_threads=1 bot_tsan

#run all tasks except interactive
$0 all

#manual play with gdb trace if segfault
$0 play_gdb

#normal play
$0 play

#build with latests installed clang and play
$0 --cmake_clang=1 play
#build with clang-3.8 and play
$0 --cmake_clang=-3.8 play

# run server with debug in gdb
$0 server_gdb

# run server without debug in gdb
$0 server_gdb_nd

# with periodic profiler
$0 stress --options_add=headless,headless_optimize,info --clients_num=10 -profiler_print_interval=5

$0 stress_tsan  --clients_autoexit=30 --clients_runs=5 --clients_sleep=25 --options_add=headless

$0 --cgroup=10g bot_tsannta --address=192.168.0.1 --port=30005

# debug touchscreen gui. use irrlicht branch ogl-es with touchscreen patch /build/android/irrlicht-touchcount.patch
$0 --build_name="_touch_asan" --cmake_touchscreen=1 --cmake_add="-DIRRLICHT_INCLUDE_DIR=../../irrlicht/include -DIRRLICHT_LIBRARY=../../irrlicht/lib/Linux/libIrrlicht.a -DENABLE_GLES=1" -touchscreen=0 play_asan

# sometimes *san + debug doesnt work with leveldb
$0 --cmake_leveldb=0
#or buid and use custom leveldb
$0 --cmake_add="-DLEVELDB_INCLUDE_DIR=../../leveldb/include -DLEVELDB_LIBRARY=../../leveldb/out-static/libleveldb.a"

#if you have installed Intel(R) VTune(TM) Amplifier
$0 play_vtune --vtune_gui=1
$0 bot_vtune --autoexit=60 --vtune_gui=1
$0 bot_vtune --autoexit=60
$0 stress_vtune

# google-perftools https://github.com/gperftools/gperftools
$0 --gperf_heapprofile=1 --gperf_heapcheck=1 --gperf_cpuprofile=1 bot_gperf
$0 --gperf_heapprofile=1 --gperf_heapcheck=1 --gperf_cpuprofile=1 --options_add=headless,headless_optimize,info --clients_num=50 -profiler_print_interval=10 stress_gperf

# stress test of flowing liquid
$0 --options_add=world_water

# stress test of falling sand
$0 --options_add=world_sand

$0 --cmake_minetest=1 --build_name=_minetest --options_add=headless,headless_optimize --address=cool.server.org --port=30001 --clients_num=25 clients

# timelapse video
$0 timelapse

#fly
$0 --options_add=server_optimize,far fly
$0 -farmesh=1 --options_add=mg_math_tglag,server_optimize,far -static_spawnpoint=10000,30030,-22700 fly
$0 --options_bot=fall1 -continuous_forward=1 bot
};

no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use strict;
use feature qw(say);
use Data::Dumper ();
$Data::Dumper::Sortkeys = $Data::Dumper::Useqq = $Data::Dumper::Indent = $Data::Dumper::Terse = 1;
#use JSON;
use Cwd   ();
use POSIX ();
use Time::HiRes qw(sleep);

sub sy (@);
sub dmp (@);

our $signal;
our $script_path;

BEGIN {
    ($0) =~ m|^(.+)[/\\].+?$|;    #v0w
    $script_path = $1;
    ($script_path = ($script_path =~ m{^/} ? $script_path . '/' : Cwd::cwd() . '/' . $script_path . '/')) =~ tr|\\|/|;
}

our $root_path = $script_path . '../../';
1 while $root_path =~ s{[^/\.]+/\.\./}{}g;
my @ar = grep { !/^-/ } @ARGV;
my $logdir_add = (@ar == 1 and $ar[0] =~ /^\w+$/) ? '.' . $ar[0] : '';
our $config = {};
our $g = {date => POSIX::strftime("%Y-%m-%dT%H-%M-%S", localtime()),};

sub init_config () {
    (my $clang_version = `bash -c "compgen -c clang | grep 'clang-[[:digit:]]' | sort --version-sort --reverse | head -n1"`) =~ s/^clang//;
    $config = {
        #address           => '::1',
        port              => 60001,
        clients_start     => 0,
        clients_num       => 5,
        autoexit          => 600,
        clang_version     => $clang_version,                                               #"", # "-3.6",
        autotest_dir_rel  => 'util/autotest/',
        build_name        => '',
        root_prefix       => $root_path . 'auto',
        root_path         => $root_path,
        date              => $g->{date},
        world             => $script_path . 'world',
        config            => $script_path . 'auto.json',
        logdir            => $script_path . 'logs.' . $g->{date} . $logdir_add,
        screenshot_dir    => 'screenshot.' . $g->{date},
        env               => 'OPENSSL_armcap=0',
        gdb_stay          => 0,                                                            # dont exit from gdb
        runner            => 'nice ',
        name              => 'bot',
        go                => '--go',
        gameid            => 'default',
        tsan_opengl_fix   => 1,
        tsan_leveldb_fix  => 1,
        options_display   => ($ENV{DISPLAY} ? '' : 'headless'),
        options_bot       => 'bot,bot_random',
        makej             => '$(nproc || sysctl -n hw.ncpu || echo 2)',
        cmake_minetest    => undef,
        cmake_leveldb     => undef,
        cmake_nothreads   => '-DENABLE_THREADS=0 -DHAVE_THREAD_LOCAL=0 -DHAVE_FUTURE=0',
        cmake_nothreads_a => '-DENABLE_THREADS=0 -DHAVE_THREAD_LOCAL=1 -DHAVE_FUTURE=0',
        cmake_opts     => [qw(CMAKE_C_COMPILER CMAKE_CXX_COMPILER CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER)],
        valgrind_tools => [qw(memcheck exp-sgcheck exp-dhat   cachegrind callgrind massif exp-bbv)],
        cgroup         => ($^O ~~ 'linux' ? 1 : undef),
        tee            => '2>&1 | tee -a ',
        run_task       => 'run_single',
        cache_clear => 0,    # remove cache dir before start client
        world_clear => 0,    # remove old world before start client
             #cmake_add     => '', # '-DIRRLICHT_INCLUDE_DIR=~/irrlicht/include -DIRRLICHT_LIBRARY=~/irrlicht/lib/Linux/libIrrlicht.a',
             #make_add     => '',
             #run_add       => '',
        vtune_amplifier => '~/intel/vtune_amplifier_xe/bin64/',
        vtune_collect   => 'hotspots',                            # for full list: ~/intel/vtune_amplifier_xe/bin64/amplxe-cl -help collect
    };

    map { /^--(\w+)(?:=(.*))/ and $config->{$1} = $2; } @ARGV;
    $config->{clang_version} =~ s/\s+$//;
}
init_config();

our $options = {
    default => {
        name                    => 'autotest',
        enable_sound            => 0,
        autojump                => 1,
        respawn_auto            => 1,
        disable_anticheat       => 1,
        reconnects              => 10000,
        profiler_print_interval => 100000,
        default_game            => $config->{gameid},
        max_users               => 4000,
    },
    no_exit => {
        autoexit => 0,
    },
    info => {
        -info => 1,
    },
    verbose => {
        #debug_log_level          => 'verbose',
        -verbose => 1,
        #enable_mapgen_debug_info => 1,
    },
    bot => {
        fps_max => 30,
    },
    bot_random => {
        random_input       => 1,
        continuous_forward => 1,
    },
    bot_forward => {
        continuous_forward => 1,
    },
    headless => {
        video_driver     => 'null',
        enable_sound     => 0,
        enable_clouds    => 0,
        enable_fog       => 0,
        enable_particles => 0,
        enable_shaders   => 0,
    },
    headless_optimize => {
        fps_max           => 10,
        headless_optimize => 1,
    },
    software => {
        video_driver => 'software',
    },
    timelapse => {
        timelapse                   => 1,
        enable_fog                  => 0,
        enable_particles            => 0,
        active_block_range          => 8,
        max_block_generate_distance => 8,
        max_block_send_distance     => 8,
        weather_biome               => 1,
        screenshot_path             => $config->{autotest_dir_rel} . $config->{screenshot_dir},
    },
    world_water => {
        -world    => $script_path . 'world_water',
        mg_name   => 'math',
        mg_params => {"layers" => [{"name" => "default:water_source"}]},
        mg_math => {"generator" => "mengersponge"},
    },
    world_sand => {
        -world    => $script_path . 'world_sand',
        mg_name   => 'math',
        mg_params => {"layers" => [{"name" => "default:sand"}]},
        mg_math => {"generator" => "mengersponge"},
    },
    world_torch => {
        -world    => $script_path . 'world_torch',
        mg_params => {"layers" => [{"name" => "default:torch"}, {"name" => "default:glass"}]},
    },
    world_rooms => {
        #-world    => $script_path . 'world_rooms',
        mg_name   => 'math',
        mg_math => {"generator" => "rooms"},
    },
    mg_math_tglag => {
        -world            => $script_path . 'world_math_tglad',
        mg_name           => 'math',
        mg_math           => {"N" => 30, "generator" => "tglad", "mandelbox_scale" => 1.5, "scale" => 0.000333333333,},
        static_spawnpoint => '30010,30010,-30010',
        mg_float_islands  => 0,
        mg_flags          => '',                                                                                          # "trees",
    },
    fall1 => {
        -world            => $script_path . 'world_fall1',
        mg_name           => 'math',
        mg_math           => {"generator" => "menger_sponge"},
        static_spawnpoint => '-70,20020,-190',
        mg_float_islands  => 0,
        mg_flags          => '',                                                                                          # "trees",
    },

    far => {
        max_block_generate_distance => 50,
        max_block_send_distance     => 50,
    },
    server_optimize => {
        chunksize                  => 3,
        active_block_range         => 1,
        weather                    => 0,
        abm_interval               => 20,
        nodetimer_interval         => 20,
        active_block_mgmt_interval => 20,
        server_occlusion           => 0,
    },
    client_optimize => {
        viewing_range => 15,
    },
    creative => {
        default_privs_creative => 'interact,shout,fly,fast,noclip',
        #default_privs => 'interact,shout,fly,fast,noclip',
        creative_mode      => 1,
        free_move          => 1,
        noclip             => 1,
        enable_damage      => 0,
    },
    fly_forward => {
        crosshair_alpha    => 0,
        time_speed         => 0,
        enable_minimap     => 0,
        random_input       => 0,
        static_spawnpoint  => '0,50,0',
        creative_mode      => 1,
        free_move          => 1,
        enable_damage      => 0,
        continuous_forward => 1,
    },
    fps1 => {
        fps_max => 2,
        viewing_range => 1000,
        #viewing_range_max => 1000,
        wanted_fps => 1,
    },
    stay => {
        continuous_forward => 0,
    },
    fast => {
        fast_move => 1, movement_speed_fast => 30,
    },
    bench1 => {fixed_map_seed => 1, -autoexit => 60, max_block_generate_distance => 100, max_block_send_distance => 100,},
};

map { /^-(\w+)(?:=(.*))/ and $options->{opt}{$1} = $2; } @ARGV;

our $commands = {
    init => sub { init_config(); 0 },
    prepare => sub {
        $config->{clang_version} = $config->{cmake_clang} if $config->{cmake_clang} and $config->{cmake_clang} ne '1';
        $g->{build_name} .= $config->{clang_version} if $config->{cmake_clang};
        chdir $config->{root_path};
        rename qw(CMakeCache.txt CMakeCache.txt.backup);
        rename qw(src/cmake_config.h src/cmake_config.backup);
        sy qq{mkdir -p $config->{root_prefix}$g->{build_name} $config->{logdir}};
        chdir "$config->{root_prefix}$g->{build_name}";
        rename $config->{config} => $config->{config} . '.old';
        return 0;
    },
    cmake => sub {
        return if $config->{no_cmake};
        my %D;
        $D{CMAKE_RUNTIME_OUTPUT_DIRECTORY} = "`pwd`";    # -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=`pwd`
        local $config->{cmake_clang} = 1, local $config->{cmake_debug} = 1, $D{SANITIZE_THREAD}  = 1, if $config->{cmake_tsan};
        local $config->{cmake_clang} = 1, local $config->{cmake_debug} = 1, $D{SANITIZE_ADDRESS} = 1, if $config->{cmake_asan};
        local $config->{cmake_clang} = 1, local $config->{cmake_debug} = 1, $D{SANITIZE_MEMORY}  = 1,
          if $config->{cmake_msan};
        local $config->{cmake_clang} = 1, local $config->{cmake_debug} = 1, local $config->{keep_luajit} = 1, $D{SANITIZE_UNDEFINED} = 1,
          if $config->{cmake_usan};

        $D{ENABLE_LUAJIT}      = 0                            if $config->{cmake_debug} and !$config->{keep_luajit};
        $D{ENABLE_LUAJIT}      = $config->{cmake_luajit}      if defined $config->{cmake_luajit};
        $D{DEBUG}              = 1                            if $config->{cmake_debug};
        $D{MINETEST_PROTO}     = $config->{cmake_minetest}    if defined $config->{cmake_minetest};
        $D{ENABLE_LEVELDB}     = $config->{cmake_leveldb}     if defined $config->{cmake_leveldb};
        $D{ENABLE_SCTP}        = $config->{cmake_sctp}        if defined $config->{cmake_sctp};
        $D{USE_TOUCHSCREENGUI} = $config->{cmake_touchscreen} if defined $config->{cmake_touchscreen};
        $D{USE_GPERF}          = $config->{cmake_gperf}       if defined $config->{cmake_gperf};

        $D{CMAKE_C_COMPILER}     = qq{`which clang$config->{clang_version}`},
          $D{CMAKE_CXX_COMPILER} = qq{`which clang++$config->{clang_version}`}
          if $config->{cmake_clang};
        $D{BUILD_CLIENT} = (0 + !$config->{no_build_client});
        $D{BUILD_SERVER} = (0 + !$config->{no_build_server});
        $D{uc($_)} = $config->{lc($_)} for grep { length $config->{lc($_)} } @{$config->{cmake_opts}};
        #warn 'D=', Data::Dumper::Dumper \%D;
        my $D = join ' ', map { '-D' . $_ . '=' . ($D{$_} =~ /\s/ ? qq{"$D{$_}"} : $D{$_}) } sort keys %D;
        sy qq{cmake .. $D @_ $config->{cmake_int} $config->{cmake_add} $config->{tee} $config->{logdir}/autotest.$g->{task_name}.cmake.log};
    },
    make => sub {
        local $config->{make_add} = $config->{make_add};
        $config->{make_add} .= " V=1 VERBOSE=1 " if $config->{make_verbose};
        sy qq{nice make -j $config->{makej} $config->{make_add} $config->{tee} $config->{logdir}/autotest.$g->{task_name}.make.log};
    },
    run_single => sub {
        sy qq{rm -rf ${root_path}cache/media/* } if $config->{cache_clear} and $root_path;
        sy qq{rm -rf $config->{world} } if $config->{world_clear} and $config->{world};
        #my $args = join ' ', map { '--' . $_ . ' ' . $config->{$_} } grep { $config->{$_} } qw(gameid world address port config autoexit);
        sy qq{$config->{env} $config->{runner} @_ ./freeminer $config->{go} --logfile $config->{logdir}/autotest.$g->{task_name}.game.log }
          . options_make([qw(gameid world address port config autoexit verbose)])
          . qq{$config->{run_add} $config->{tee} $config->{logdir}/autotest.$g->{task_name}.out.log };
        0;
    },
    run_single_tsan => sub {
        local $config->{options_display} = 'software' if $config->{tsan_opengl_fix} and !$config->{options_display};
        local $config->{cmake_leveldb} //= 0 if $config->{tsan_leveldb_fix};
        local $config->{runner} = $config->{runner} . " env TSAN_OPTIONS=second_deadlock_stack=1 ";
        local $options->{opt}{enable_minimap} = 0;    # too unsafe
        commands_run($config->{run_task});
    },

    valgrind => sub {
        local $config->{runner} = $config->{runner} . " valgrind @_";
        commands_run($config->{run_task});
    },
    run_server_simple => sub {
        my $fork = $config->{server_bg} ? '&' : '';
        sy
qq{$config->{env} $config->{runner} @_ ./freeminerserver $config->{tee} $config->{logdir}/autotest.$g->{task_name}.server.out.log $fork};
    },
    run_server => sub {
        my $fork = $config->{server_bg} ? '&' : '';
        #my $args = join ' ', map { '--' . $_ . ' ' . $config->{$_} } grep { $config->{$_} } qw(gameid world port config autoexit);
        sy qq{$config->{env} $config->{runner} @_ ./freeminerserver --logfile $config->{logdir}/autotest.$g->{task_name}.game.log }
          . options_make([qw(gameid world port config autoexit verbose)])
          . qq{ $config->{run_add} $config->{tee} $config->{logdir}/autotest.$g->{task_name}.server.out.log $fork};
    },
    run_clients => sub {
        sy qq{rm -rf ${root_path}cache/media/* } if $config->{cache_clear} and $root_path;
        for (0 .. ($config->{clients_runs} || 0)) {
            my $autoexit = $config->{clients_autoexit} || $config->{autoexit};
            local $config->{address} = '::1' if not $config->{address};
            #my $args = join ' ',
            #  map { '--' . $_ . ' ' . $config->{$_} } grep { $config->{$_} } qw( address gameid world address port config);
            for ($config->{clients_start} .. $config->{clients_num}) {
                sy
qq{$config->{env} $config->{runner} @_ ./freeminer --name $config->{name}$_ --go --autoexit $autoexit --logfile $config->{logdir}/autotest.$g->{task_name}.game.log }
                  . options_make([qw( address gameid world address port config verbose)])
                  . qq{ $config->{run_add} $config->{tee} $config->{logdir}/autotest.$g->{task_name}.$config->{name}$_.err.log & };
                sleep $config->{clients_spawn_sleep} // 0.2;
            }
            sleep $config->{clients_sleep} || 1 if $config->{clients_runs};
        }
    },
    symbolize => sub {
        sy
qq{asan_symbolize$config->{clang_version} < $config->{logdir}/autotest.$g->{task_name}.out.log | c++filt > $config->{logdir}/autotest.$g->{task_name}.out.symb.log};
    },
    cgroup => sub {
        return 0 unless $config->{cgroup};
        local $config->{cgroup} = '4G' if $config->{cgroup} eq 1;
        sy
qq(sudo sh -c "mkdir /sys/fs/cgroup/memory/0; echo $$ > /sys/fs/cgroup/memory/0/tasks; echo $config->{cgroup} > /sys/fs/cgroup/memory/0/memory.limit_in_bytes");
    },
    timelapse_video => sub {
        sy
qq{ cat ../$config->{autotest_dir_rel}$config->{screenshot_dir}/*.png | ffmpeg -f image2pipe -i - -vcodec libx264 ../$config->{autotest_dir_rel}timelapse-$config->{date}.mp4 };
    },
    sleep => sub {
        sleep $_[0] || 1;
        0;
    },
    fail => sub {
        warn 'fail:', join ' ', @_;
    },

};

our $tasks = {
    build_normal => [sub { $g->{build_name} ||= '_normal'; 0 }, 'prepare', 'cmake', 'make',],
    build       => [\'build_normal'],                                                                              #'
    build_debug => [sub { $g->{build_name} .= '_debug'; 0 }, {-cmake_debug => 1,}, 'prepare', 'cmake', 'make',],
    build_nothreads => [sub { $g->{build_name} .= '_nt'; 0 }, 'prepare', ['cmake', $config->{cmake_nothreads}], 'make',],
    build_server       => [{-no_build_client => 1, -no_build_server => 0,}, 'build_normal',],
    build_server_debug => [{-no_build_client => 1, -no_build_server => 0,}, 'build_debug',],
    build_client       => [{-no_build_client => 0, -no_build_server => 1,}, 'build_normal',],
    build_client_debug => [{-no_build_client => 0, -no_build_server => 1,}, 'build_debug',],
    bot                => [{-no_build_client => 0, -no_build_server => 1,}, 'build_normal', 'run_single'],
    #run_single => ['run_single'],
    clang => ['prepare', {-cmake_clang => 1,}, 'cmake', 'make',],
    build_tsan => [sub { $g->{build_name} .= '_tsan'; 0 }, {-cmake_tsan => 1,}, 'prepare', 'cmake', 'make',],
    bot_tsan   => [{-no_build_server => 1,}, 'build_tsan', 'cgroup', 'run_single_tsan',],
    bot_tsannt => sub {
        $g->{build_name} .= '_nt';
        local $config->{no_build_server} = 1;
        local $config->{cmake_int}       = $config->{cmake_int} . $config->{cmake_nothreads};
        commands_run('bot_tsan');
    },
    bot_tsannta => sub {
        $g->{build_name} .= '_nta';
        local $config->{no_build_server} = 1;
        local $config->{cmake_int}       = $config->{cmake_int} . $config->{cmake_nothreads_a};
        commands_run('bot_tsan');
    },
    build_asan => [
        sub {
            $g->{build_name} .= '_asan';
            0;
        }, {
            -cmake_asan => 1,
            #-env=>'ASAN_OPTIONS=symbolize=1 ASAN_SYMBOLIZER_PATH=llvm-symbolizer$config->{clang_version}',
        },
        'prepare',
        'cmake',
        'make',
    ],
    build_msan => [
        sub {
            $g->{build_name} .= '_msan';
            0;
        }, {
            -cmake_msan => 1,
        },
        'prepare',
        'cmake',
        'make',
    ],
    build_usan => [
        sub {
            $g->{build_name} .= '_usan';
            0;
        }, {
            -cmake_usan => 1,
        },
        'prepare',
        'cmake',
        'make',
    ],
    build_gperf => [
        sub {
            $g->{build_name} .= '_gperf';
            0;
        }, {
            -cmake_gperf => 1,
        },
        'prepare',
        'cmake',
        'make',
    ],
    bot_asan => [
        {-no_build_server => 1,},
        'build_asan',
        $config->{run_task},
        'symbolize',
    ],
    bot_asannta => sub {
        $g->{build_name} .= '_nta';
        local $config->{cmake_int} = $config->{cmake_int} . $config->{cmake_nothreads_a};
        commands_run('bot_asan');
    },
    bot_msan => [
        {-no_build_server => 1,},
        'build_msan',
        $config->{run_task},
        'symbolize',
    ],
    bot_usan => [
        {-no_build_server => 1, -env => 'UBSAN_OPTIONS=print_stacktrace=1',},
        'build_usan',
        $config->{run_task},
        'symbolize',
    ],
    debug     => ['build_client_debug', $config->{run_task},],
    bot_debug => ['build_client_debug', $config->{run_task},],

    nothreads => [{-no_build_server => 1,}, \'build_nothreads', $config->{run_task},],    #'
    (
        map {
            'valgrind_' . $_ => [
                {build_name => ''},
                #{build_name => 'debug'}, 'prepare', ['cmake', qw(-DBUILD_SERVER=0 -DENABLE_LUAJIT=0 -DDEBUG=1)], 'make',
                \'build_debug',                                                           #'
                ['valgrind', '--tool=' . $_],
              ],
        } @{$config->{valgrind_tools}}
    ),

    (
        map {
            my $buildname = $_;
            (
                $buildname => sub {
                    return 1 if $config->{all_run};
                    local $g->{build_name} = $g->{build_name} . '_' . $buildname;
                    local $config->{'cmake_' . $buildname} = 1;
                    @_ = ('build') if !@_;
                    for (@_) { my $r = commands_run($_); return $r if $r; }
                },

                (
                    #map { $buildname . '_' . $_ => [[\$buildname, $_]] }
                    map { $_ . '_' . $buildname => [[\$buildname, $_]] }
                      qw(build build_client build_client_debug build_server build_server_debug stress)
                ),    # '

                'bot_' . $buildname => sub {
                    my $name = shift;
                    local $config->{no_build_server} = 1;
                    local $config->{'cmake_' . $buildname} = 1;
                    #local $config->{cmake_int}       = $config->{cmake_int} . $config->{'cmake_' . $buildname};
                    if ($name) {
                        $g->{build_name} .= '_' . $buildname;
                        commands_run('bot_' . $name);
                    } else {
                        commands_run('build_client_' . $buildname);
                        commands_run($config->{run_task});
                    }
                }, (
                    map {
                        "bot_${buildname}_" . $_ => [['bot_' . $buildname, $_,]]
                    } qw(tsan tsannt asan usan gdb debug)
                ),
              )
        } qw(minetest sctp)
    ),
    stress => ['build_normal', {-server_bg => 1,}, 'run_server', ['sleep', 10], 'clients_run',],

    clients_run => [{build_name => '_normal'}, 'run_clients'],
    clients => ['build_client', 'clients_run'],

    stress_tsan => [
        {-no_build_client => 1, -no_build_server => 0, -server_bg => 1,}, 'build_tsan', 'cgroup',
        'run_server', ['sleep', 10], {build_name => '_normal', -cmake_tsan => 0,}, 'clients',

        # todo split build and run:
        #{-no_build_client => 1, -no_build_server => 0, -server_bg => 1,}, 'build_tsan', 'cgroup',
        #{build_name => '_normal', -cmake_tsan => 0,}, 'build_client',
        #{build_name => '_tsan',}, 'run_server',
        #{build_name => '_normal',}, ['sleep', 10], 'clients_run',
    ],
    stress_asan => [
        {-no_build_client => 1, -no_build_server => 0, -server_bg => 1,}, 'build_asan', 'cgroup',
        'run_server', ['sleep', 10], {build_name => '_normal', -cmake_asan => 0,}, 'clients',
    ],

    stress_massif => [
        'build_client',
        sub {
            local $config->{run_task} = 'run_server';
            commands_run('valgrind_massif');
        },
        ['sleep', 10],
        'clients_run',
    ],

    debug_mapgen => [
        #{build_name => 'debug'},
        sub {
            local $config->{world} = "$config->{logdir}/world_$g->{task_name}";
            commands_run('debug');
          }
    ],
    gdb => sub {
        local $config->{runner} =
          $config->{runner} . q{gdb -ex 'run' -ex 't a a bt' } . ($config->{gdb_stay} ? '' : q{ -ex 'cont' -ex 'quit' }) . q{ --args };
        @_ = ('debug') if !@_;
        for (@_) { my $r = commands_run($_); return $r if $r; }
    },

    server       => [{-options_add => 'no_exit'}, 'build_server',       'run_server'],
    server_debug => [{-options_add => 'no_exit'}, 'build_server_debug', 'run_server'],
    server_gdb => [{-options_add => 'no_exit'}, ['gdb', 'server_debug']],
    server_gdb_nd => [{-options_add => 'no_exit'}, 'build_server', ['gdb', 'run_server']],

    bot_gdb    => ['build_client_debug', ['gdb', 'run_single']],
    bot_gdb_nd => ['build_client',       ['gdb', 'run_single']],

    vtune => sub {
        sy 'echo 0|sudo tee /proc/sys/kernel/yama/ptrace_scope';
        local $config->{runner} =
          $config->{runner} . qq{$config->{vtune_amplifier}amplxe-cl -collect $config->{vtune_collect} -r $config->{logdir}/rh0};
        local $config->{run_escape} = '\\\\';
        @_ = ('debug') if !@_;
        for (@_) { my $r = commands_run($_); return $r if $r; }
    },
    vtune_report => sub {
        if ($config->{vtune_gui}) {
            sy qq{$config->{vtune_amplifier}amplxe-gui $config->{logdir}/rh0};    # -limit=1000
        } else {
            for my $report (qw(hotspots top-down)) {                              # summary callstacks
                sy
qq{$config->{vtune_amplifier}amplxe-cl -report $report -report-width=250 -report-output=$config->{logdir}/vtune.$report.log -r $config->{logdir}/rh0}
                  ;                                                               # -limit=1000
            }
        }
    },
    bot_vtune => ['build_client_debug', ['vtune', 'run_single'], 'vtune_report'],
    stress_vtune => [
        #'build_debug',sub { commands_run('vtune', 'run_server');}, ['sleep', 10], 'clients_run',
        {                                                                         #-no_build_client => 1, -no_build_server => 0,
            -server_bg => 1,
        },
        'build_debug',
        [\'vtune', 'run_server'],
        ['sleep',  10],
        #{build_name => '_normal'},
        'clients',

    ],

    gperf => sub {
        my $flags;
        $flags .= " MALLOCSTATS=9 ";
        $flags .= " HEAPCHECK=normal " if $config->{gperf_heapcheck};
        $flags .= " HEAPPROFILE=$config->{logdir}/heap.out " if $config->{gperf_heapprofile};
        $flags .= " CPUPROFILE=$config->{logdir}/cpu.out " if $config->{gperf_cpuprofile};
        local $config->{runner} = $flags . ' ' . $config->{runner};
        @_ = ('debug') if !@_;
        for (@_) { my $r = commands_run($_); return $r if $r; }
    },
    bot_gperf => [{-no_build_server => 1,}, 'build_gperf', ['gperf', 'run_single'], 'gperf_report'],
    play_gperf => [{-no_build_server => 1,}, [\'play_task', 'build_gperf', [\'gperf', $config->{run_task}], 'gperf_report']],

    stress_gperf => [
        {-no_build_client => 1, -no_build_server => 0, -server_bg => 1,}, 'build_gperf',
        ['gperf', 'run_server'], ['sleep', 10], {build_name => '_normal', -cmake_gperf => 0,}, 'clients',
    ],

    play_task => sub {
        return 1 if $config->{all_run};
        local $config->{no_build_server} = 1;
        local $config->{go}              = undef;
        local $config->{options_bot}     = undef;
        local $config->{autoexit}        = undef;
        for (@_) { my $r = commands_run($_); return $r if $r; }
    },

    (
        map { 'play_' . $_ => [{-no_build_server => 1,}, [\'play_task', 'bot_' . $_]] }
          qw(tsan asan msan usan asannta minetest minetest_debug)
    ), (
        map { 'play_' . $_ => [{-no_build_server => 1,}, [\'play_task', $_]] } qw(debug gdb nothreads vtune),
        map { 'valgrind_' . $_ } @{$config->{valgrind_tools}},
    ),

    (map { 'gdb_' . $_ => [[\'gdb', $_]] } map { $_, 'bot_' . $_, 'play_' . $_ } qw(tsan asan msan usan asannta minetest minetest_debug)),
    (map { 'gdb_' . $_ => [[\'gdb', $_]] } map {$_} qw(server)),

    play => [{-no_build_server => 1,}, [\'play_task', 'build_normal', $config->{run_task}]],    #'
    timelapse_play => [{-options_int => 'timelapse',}, \'play', 'timelapse_video'],             #'
    fly => [{-options_int => 'fly_forward', -options_bot => '',}, \'bot',],                                          #'
    timelapse_fly => [{-options_int => 'timelapse,fly_forward', -options_bot => '',}, \'bot', 'timelapse_video'],    #'
    timelapse_stay => [{-options_int => 'timelapse,fly_forward,stay,far,fps1', -options_bot => '',}, \'bot', 'timelapse_video'],    #'
    bench1 => [{-options_int => 'bench1,fly_forward,fast',}, \'bot'],                                                #'
    up => sub {
        my $cwd = Cwd::cwd();
        chdir $config->{root_path};
        sy qq{(git stash && git pull --rebase >&2) | grep -v "No local changes to save" && git stash pop};
        sy qq{git submodule update --init --recursive};
        chdir $cwd;
        return 0;
    },

    kill_client => sub {
        sy qq{killall freeminer};
        return 0;
    },
    kill_server => sub {
        sy qq{killall freeminerserver};
        return 0;
    },
    kill => ['kill_client', 'kill_server'],
};

sub dmp (@) { say +(join ' ', (caller)[0 .. 5]), ' ', Data::Dumper::Dumper \@_ }

sub sy (@) {
    say 'running ', join ' ', @_;
    system @_;
    if ($? == -1) {
        say "failed to execute: $!";
        return $?;
    } elsif ($? & 127) {
        $signal = $? & 127;
        say "child died with signal ", ($signal), ", " . (($? & 128) ? 'with' : 'without') . " coredump";
        return $?;
    } else {
        return $? >> 8;
    }
}

sub array (@) {
    local @_ = map { ref $_ eq 'ARRAY' ? @$_ : $_ } (@_ == 1 and !defined $_[0]) ? () : @_;
    wantarray ? @_ : \@_;
}

sub json (@) {
    local *Data::Dumper::qquote = sub {
        $_[0] =~ s/\\/\\\\/g, s/"/\\"/g for $_[0];
        return $_[0] + 0 eq $_[0] ? $_[0] : '"' . $_[0] . '"';
    };
    return \(Data::Dumper->new(\@_)->Pair(':')->Terse(1)->Indent(0)->Useqq(1)->Useperl(1)->Dump());
}

sub options_make(;$$) {
    my ($mm, $m) = @_;
    my ($rm, $rmm);

    $rmm = {map { $_ => $config->{$_} } grep { $config->{$_} } array(@$mm)};

    $m ||= [
        map { split /[,;]+/ } map { array($_) } 'default', $config->{options_display}, $config->{options_bot},
        $config->{options_int}, $config->{options_add}, 'opt'
    ];
    for my $name (array(@$m)) {
        $rm->{$_} = $options->{$name}{$_} for sort keys %{$options->{$name}};
        for my $k (sort keys %$rm) {
            if ($k =~ /^-/) {
                $rmm->{$'} = $rm->{$k};
                delete $rm->{$k};
                next;
            }
            next if !ref $rm->{$k};
            #($rm->{$k} = JSON::encode_json($rm->{$k})) =~ s/"/$config->{run_escape}\\"/g;    #"
            ($rm->{$k} = ${json($rm->{$k})}) =~ s/"/$config->{run_escape}\\"/g;    #"
        }
    }

    return join ' ', (map {"--$_ $rmm->{$_}"} sort keys %$rmm), (map {"-$_=$rm->{$_}"} sort keys %$rm);
}

sub command_run(@);

sub command_run(@) {
    my $cmd = shift;
    #say "command_run $cmd ", @_;
    if ('CODE' eq ref $cmd) {
        return $cmd->(@_);
    } elsif ('HASH' eq ref $cmd) {
        for my $k (sort keys %$cmd) {
            if ($k =~ /^-+(.+)/) {
                $config->{$1} = $cmd->{$k};
            } else {
                $g->{$k} = $cmd->{$k};
            }
        }
    } elsif ('ARRAY' eq ref $cmd) {
        #for (@{$cmd}) {
        my $r = command_run(array $cmd, @_);
        warn("command $_ returned $r"), return $r if $r;
        #}
    } elsif ($cmd) {
        #return sy $cmd, @_;
        return commands_run($cmd, @_);
    } else {
        dmp 'no cmd', $cmd;
    }
}

sub commands_run(@);

sub commands_run(@) {
    my $name = shift;
    #say "commands_run $name ", @_;
    my $c = $commands->{$name} || $tasks->{$name};
    if ('SCALAR' eq ref $name) {
        commands_run($$name, @_);
    } elsif ('ARRAY' eq ref $c) {
        for (@{$c}) {
            my $r = command_run $_, @_;
            warn("command $_ returned $r"), return $r if $r;
        }
    } elsif ($c) {
        return command_run $c, @_;
    } elsif (ref $name) {
        return command_run $name, @_;
        #} elsif ($options->{$name}) {
        #    $config->{options_add} .= ',' . $name;
        #    #command_run({-options_add => $name});
        #    return 0;
    } else {
        say 'msg ', $name;
        return 0;
    }
}

sub task_start(@) {
    my $name = shift;
    $name = $1, unshift @_, $2 if $name =~ /^(.*?)=(.*)$/;
    say "task start $name ", @_;
    #$g = {task_name => $name, build_name => $name,};
    $g->{task_name}  = $name;
    $g->{build_name} = $config->{build_name};
    #task_run($name, @_);
    commands_run($name, @_);
}

my $task_run = [grep { !/^-/ } @ARGV];
$task_run = [
    @$task_run,
    qw(bot_tsan bot_asan bot_usan bot_tsannt bot_tsannta valgrind_memcheck bot_minetest_tsan bot_minetest_tsannt bot_minetest_asan bot_minetest_usan)
  ]
  if !@$task_run or 'default' ~~ $task_run;
if ('all' ~~ $task_run) {
    $task_run = [sort keys %$tasks];
    $config->{all_run} = 1;
}

unless (@ARGV) {
    say $help;
    say "possible tasks:";
    print "$_ " for sort keys %$tasks;
    say "\n\n but running default list: ", join ' ', @$task_run;
    say '';
    say "possible presets in --options_add=... :";
    print "$_ " for sort keys %$options;
    say '';
    sleep 1;
}

for my $task (@$task_run) {
    init_config();
    warn "task failed [$task]" if task_start($task);
    last if $signal ~~ [2, 3];
}
