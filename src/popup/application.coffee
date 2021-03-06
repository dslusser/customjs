
Kefir = require 'kefir'
Const = require './constants'

{List, fromJS} = require 'immutable'
{comp, filter, map} = require 'transducers-js'

window.im = require 'immutable'
storage = require './utils/storage'

register = (stream, messageType, handler) ->
  xform = comp(
    filter (x) => x.first() is messageType
    map (x) => x.rest()
  )
  stream.transduce(xform).onValue handler

class Application
  constructor: (@view) ->
    @stream = Kefir.emitter()

    @websites = Const.INITIAL_WEBSITES

    # For debugging
    @stream.map((x) => x.toJS()).log 'stream'

    @on 'update-script',  (x) => @update x.first()
    @on 'change-website', (x) => @load x.first()
    @on 'save-script',   @save.bind this
    @on 'remove-script', @remove.bind this
    @on 'remove-draft',  @removeDraft.bind this
    @on 'state-changed', @render.bind this

  on: (eventName, handler) ->
    register @stream, eventName, handler

  emit: ->
    @stream.emit new List arguments
    return

  load: (website) ->
    @websites.selected = website
    @websites.current ?= website

    storage.getWebsiteData website, @receive.bind this

  receive: (data) ->
    all = data.websites

    if all.indexOf(@websites.current) is -1
      all.push @websites.current

    @websites.all = all

    # Array of max 2 items (script and draft)
    @scripts = fromJS data.scripts

    if @scripts.count() is 0
      @scripts = @scripts.push fromJS Const.INITIAL_SCRIPT

    @emit 'state-changed', 'receive', data

  update: (script) ->
    state = script.get 'state'

    switch state
      when Const.INITIAL_STATE
        script   = script.set 'state', Const.DRAFT_STATE
        @scripts = @scripts.set -1, script

      when Const.DRAFT_STATE
        @scripts = @scripts.set -1, script

      else
        script   = script.set 'state', Const.DRAFT_STATE
        @scripts = @scripts.push script

    storage.setScripts @websites.selected, @scripts.toJS(), =>
      @emit 'state-changed', 'update', script

  isDraft: (script) ->
    script.get('state') is Const.DRAFT_STATE

  isInitial: (script) ->
    script.get('state') is Const.INITIAL_STATE

  save: ->
    script = @scripts.last()

    # Only modified scripts will be stored
    return unless @isDraft script

    script = script.remove 'state'
    @scripts = new List [script]

    storage.setScripts @websites.selected, @scripts.toJS(), =>
      @emit 'state-changed', 'save', script

  remove: ->
    # Only stored scripts will be removed
    return if @isInitial @scripts.last()

    @scripts = new List [fromJS Const.INITIAL_SCRIPT]

    storage.removeWebsiteData @websites.selected, =>
      @emit 'state-changed', 'remove'

  removeDraft: ->
    @scripts = @scripts.filter (x) -> x.get('state') isnt Const.DRAFT_STATE

    callback = => @emit 'state-changed', 'removeDraft'

    if @scripts.isEmpty()
      @scripts = @scripts.push fromJS Const.INITIAL_SCRIPT
      storage.removeWebsiteData @websites.selected, callback
    else
      storage.setScripts @websites.selected, @scripts.toJS(), callback

  render: ->
    # Draft will be always the last script, if exists
    script = @scripts.last()

    @view.setProps
      websites: @websites
      script: script
      draftPresent: @isDraft script
      messages:
        emit: @emit.bind this
        on: @on.bind this

module.exports = Application
