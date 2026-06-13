
const args = process.argv.slice(2);
const { exit } = require("process");
const config = require("../conf/config.json");


// 16.17.0后可以使用util.parseArgs，目前是16.11.0
const options = {
    '--arch': {
        type: 'string',
    },
    '--channel': {
        type: 'string',
    },
    '--get-arch': {
        type: 'boolean',
    },
    '--get-nwjs-url': {
        type: 'boolean',
    },
    '--get-nwjs-version': {
        type: 'boolean',
    },
    '--get-electron-url': {
        type: 'boolean',
    },
    '--get-electron-version': {
        type: 'boolean',
    },
    '--get-node-url': {
        type: 'boolean',
    },
    '--get-node-version': {
        type: 'boolean',
    },
    '--get-compiler-prefix': {
        type: 'boolean',
    },
    '--get-compiler-version': {
        type: 'boolean',
    },
    '--get-devtools-url': {
        type: 'boolean',
    },
    '--get-devtools-version': {
        type: 'boolean',
    },
    '--get-devtools-package': {
        type: 'boolean',
    },
    '--get-runtime': {
        type: 'boolean',
    },
}
const configArg = {
    arch: process.arch,
    channel: 'stable',
}

const allowedChannels = Object.keys((config.devtools && config.devtools.channels) || { stable: true });

function getDevtoolsConfig() {
    const channels = config.devtools.channels || {};
    return channels[configArg.channel] || config.devtools;
}

function getArchConfig(sectionName) {
    const section = config[sectionName];
    if (!section || !section.urls || !section.urls[configArg.arch]) {
        console.error(`Unsupported ${sectionName} arch: ${configArg.arch}`);
        exit(1);
    }
    return section.urls[configArg.arch];
}

function replaceVersion(template, version) {
    return template.replace(/\${version}/g, version);
}

for (let i = 0; i < args.length; i++) {
    if (options[args[i]]) {
        if (options[args[i]].type === 'string') {
            i++;
            if (i < args.length) {
                if (args[i - 1] === '--arch') {
                    if (args[i] === 'x64' || args[i] === 'loongarch64' || args[i] === 'arm64') {
                        configArg.arch = args[i];
                    } else {
                        console.error(`Invalid value for option --arch: ${args[i]}`);
                        exit(1);
                    }
                } else if (args[i - 1] === '--channel') {
                    if (allowedChannels.includes(args[i])) {
                        configArg.channel = args[i];
                    } else {
                        console.error(`Invalid value for option --channel: ${args[i]}`);
                        exit(1);
                    }
                }
            } else {
                console.error(`Missing value for option: ${args[i - 1]}`);
                exit(1);
            }
        } else if (options[args[i]].type === 'boolean') {
            configArg[args[i].substring(2)] = true;
        }
    }
}

if (configArg['get-arch']) {
    console.log(configArg.arch);
    exit(0);
}

if (configArg['get-nwjs-url']) {
    const nwjsConfig = getArchConfig('nwjs');
    console.log(replaceVersion(nwjsConfig.template, nwjsConfig.version));
    exit(0);
}

if (configArg['get-nwjs-version']) {
    console.log(getArchConfig('nwjs').version);
    exit(0);
}

if (configArg['get-electron-url']) {
    const electronConfig = getArchConfig('electron');
    console.log(replaceVersion(electronConfig.template, electronConfig.version));
    exit(0);
}

if (configArg['get-electron-version']) {
    console.log(getArchConfig('electron').version);
    exit(0);
}

if (configArg['get-node-url']) {
    console.log(config.node.urls[configArg.arch].template.replace(/\${version}/g, config.node.urls[configArg.arch].version));
    exit(0);
}

if (configArg['get-node-version']) {
    console.log(config.node.urls[configArg.arch].version);
    exit(0);
}

if (configArg['get-compiler-prefix']) {
    console.log(config.compiler.template.replace(/\${version}/g, config.compiler.version));
    exit(0);
}

if (configArg['get-compiler-version']) {
    console.log(config.compiler.version);
    exit(0);
}

if (configArg['get-devtools-url']) {
    const devtoolsConfig = getDevtoolsConfig();
    console.log(replaceVersion(devtoolsConfig.template, devtoolsConfig.version.replace(/\./g, '')));
    exit(0);
}

if (configArg['get-devtools-version']) {
    console.log(getDevtoolsConfig().version);
    exit(0);
}

if (configArg['get-devtools-package']) {
    console.log(getDevtoolsConfig().package || 'nw');
    exit(0);
}

if (configArg['get-runtime']) {
    console.log(getDevtoolsConfig().runtime || 'nwjs');
    exit(0);
}
