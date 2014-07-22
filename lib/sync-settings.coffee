# imports
{BufferedProcess} = require 'atom'
GitHubApi = require 'github'
_ = require 'underscore-plus'
PackageManager = require './package-manager'
fs = require 'fs'

# constants
DESCRIPTION = 'Atom configuration store operated by http://atom.io/packages/sync-settings'

module.exports =
  configDefaults:
    personalAccessToken: "<Your personal GitHub access token>"
    gistId: "<Id of gist to use for configuration store>"

  activate: ->
    # for debug
    atom.workspaceView.command "sync-settings:upload", => @upload()
    atom.workspaceView.command "sync-settings:download", => @download()

  deactivate: ->

  serialize: ->

  upload: (cb=null) ->
    files =
      "settings.json":
        content: JSON.stringify(atom.config.settings, null, '\t')
      "packages.json":
        content: JSON.stringify(@getPackages(), null, '\t')
      "keymap.cson":
        content: @fileContent atom.keymap.getUserKeymapPath()

    @createClient().gists.edit
      id: atom.config.get 'sync-settings.gistId'
      description: "automatic update by http://atom.io/packages/sync-settings"
      files: files
    , (err, res) =>
      console.error "error uploading data: "+err.message, err if err
      cb?(err, res)

  getPackages: ->
    for name,info of atom.packages.getLoadedPackages()
      {name, version, theme} = info.metadata
      {name, version, theme}

  download: (cb=null) ->
    @createClient().gists.get
      id: atom.config.get 'sync-settings.gistId'
    , (err, res) =>
      if err
        console.error("error while retrieving the gist. does it exists?", err)
        return

      settings = JSON.parse(res.files["settings.json"].content)
      console.debug "settings: ", settings
      @applySettings "", settings

      packages = JSON.parse(res.files["packages.json"].content)
      console.debug "packages: ", packages
      @installMissingPackages packages, cb

      keymap = res.files['keymap.cson']?.content
      console.debug "keymap.cson = ", res.files['keymap.cson']?.content
      fs.writeFileSync(atom.keymap.getUserKeymapPath(), res.files['keymap.cson'].content) if keymap


  createClient: ->
    token = atom.config.get 'sync-settings.personalAccessToken'
    console.debug "Creating GitHubApi client with token = #{token}"
    github = new GitHubApi
      version: '3.0.0'
      debug: true
      protocol: 'https'
    github.authenticate
      type: 'oauth'
      token: token
    github

  applySettings: (pref, settings) ->
    for key, value of settings
      keyPath = "#{pref}.#{key}"
      if _.isObject(value) and not _.isArray(value)
        @applySettings keyPath, value
      else
        console.debug "config.set #{keyPath[1...]}=#{value}"
        atom.config.set keyPath[1...], value

  installMissingPackages: (packages, cb) ->
    pending=0
    for pkg in packages
      continue if atom.packages.isPackageLoaded(pkg.name)
      pending++
      @installPackage pkg, ->
        pending--
        cb?() if pending is 0
    cb?() if pending is 0

  installPackage: (pack, cb) ->
    type = if pack.theme then 'theme' else 'package'
    console.info("Installing #{type} #{pack.name}...")
    packageManager = new PackageManager()
    packageManager.install pack, (error) =>
      if error?
        console.error("Installing #{type} #{pack.name} failed", error.stack ? error, error.stderr)
      else
        console.info("Installed #{type} #{pack.name}")
      cb?(error)

  fileContent: (filePath) ->
    try
      return fs.readFileSync(filePath, {encoding: 'utf8'}) || " "
    catch e
      console.error "Error while reading file #{filePath}. Probably doesn't exists.", e
      " "
