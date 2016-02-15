http        = require 'http'
https       = require 'https'
urlHelpers  = require 'url'
querystring = require 'querystring'
fs          = require 'fs'
readline    = require 'readline'

Q = (value) ->
  #stupid sublime
  Qpromise (resolve) -> resolve value
Qpromise = (resolver) ->
  resolved = false
  resolvedValue = null
  resolves = []
  resolve = (value) ->
    if value?.then?
      value.then (x) ->
        resolve x
    else
      resolved = true
      resolvedValue = value
      for resolve in resolves
        resolve resolvedValue
  resolver resolve
  then: (f) ->
    if resolved
      Q f resolvedValue
    else
      Qpromise (resolve) ->
        resolves.push (value) -> resolve f value
Qall = (ps) ->
  result = Q []
  for p in ps
    do (p) ->
      result = result.then (arr) ->
        p.then (v) ->
          arr.concat [v]
  result
Qdenodify = (owner, fn) ->
  (args...) ->
    Qpromise (resolve) ->
      args.push (err, results...) ->
        if err?
          resolve err: err
        else if results.length is 1
          resolve results[0]
        else
          resolve results
      try
        fn.apply owner, args
      catch err
        resolve err: err

getQ = (url, cookieOrHeader, encoding = 'utf8') ->
  options = urlHelpers.parse url
  options.method = 'GET'
  if typeof cookieOrHeader is 'string'
    options.headers = cookie: cookieOrHeader
  else if typeof cookieOrHeader is 'object'
    options.headers = cookieOrHeader
  Qpromise (resolve) ->
    h = if url.indexOf('https') is -1 then http else https
    req = h.request options, (res) ->
      res.setEncoding encoding
      body = ''
      res.on 'data', (data) ->
        body += data
      res.on 'end', ->
        res.body = body
        resolve res
    req.end()

postQ = (url, data, cookieOrHeader, encoding = 'utf8') ->
  dataString = querystring.stringify data
  options = urlHelpers.parse url
  options.method = 'POST'
  options.headers =
    'Content-Type': 'application/x-www-form-urlencoded',
    'Content-Length': dataString.length
  if typeof cookieOrHeader is 'string'
    options.headers.cookie = cookieOrHeader
  else if typeof cookieOrHeader is 'object'
    for key of cookieOrHeader
      options.headers[key] = cookieOrHeader[key]
  Qpromise (resolve) ->
    h = if url.indexOf('https') is -1 then http else https
    req = h.request options, (res) ->
      res.setEncoding encoding
      body = ''
      res.on 'data', (data) ->
        body += data
      res.on 'end', ->
        res.body = body
        resolve res
    req.end dataString



readLineQ = -> Qpromise (resolve) ->
  rl = readline.createInterface
    input: process.stdin
    output: process.stdout
  rl.question '', (input) ->
    rl.close()
    resolve input

writeFileQ = Qdenodify fs, fs.writeFile
unlinkQ = Qdenodify fs, fs.unlink


console.log 'Please wait...'

getQ 'http://golestan.ut.ac.ir/home/balancer/balancer.aspx?vv=2&cost=main'

.then (res) ->

  sid = res.headers['set-cookie'][0]
  sid = sid.substr 0, sid.indexOf ';'
  sid = sid.substr 18

  eventValidation = /id="__EVENTVALIDATION".*/g.exec(res.body)[0]
  eventValidation = eventValidation.substr 30
  eventValidation = eventValidation.substr 0, eventValidation.length - 4

  viewState = /id="__VIEWSTATE".*/g.exec(res.body)[0]
  viewState = viewState.substr 24
  viewState = viewState.substr 0, viewState.length - 4

  captchaQ = getQ 'http://golestan.ut.ac.ir/home/balancer/captcha.aspx', "ASP.NET_SessionId=#{sid}", 'binary'  
  .then (res) ->
    saveCaptchaQ = writeFileQ 'Captcha.gif', res.body, 'binary'
    console.log 'Please enter the text in the file "Captcha.gif"'
    inputQ = readLineQ()
    Qall [inputQ, saveCaptchaQ]
  .then ([input, _]) ->
    input

  captchaQ.then (cvalue) ->
    { sid, eventValidation, viewState, cvalue }

.then (data) ->
  postData =
    __EVENTVALIDATION: data.eventValidation
    __VIEWSTATE: data.viewState
    hip: data.cvalue

  postQ 'http://golestan.ut.ac.ir/home/balancer/balancer.aspx?vv=2&cost=main', postData, "ASP.NET_SessionId=#{data.sid}"

  .then (res) ->

    setCid = /setcid.*/g.exec(res.body)

    unless setCid?
      console.log 'Wrong captcha'
      fs.unlinkSync 'Captcha.gif'
      process.exit()

    unlinkQ 'Captcha.gif'
    console.log 'Loading report. Please wait...'

    setCid = setCid[0]
    setCid = setCid.substr 0, setCid.length - 2
    getQ "https://golestan.ut.ac.ir/Forms/AuthenticateUser/#{setCid}", "ASP.NET_SessionId=#{data.sid}"

  .then ->
    getQ 'https://golestan.ut.ac.ir/Forms/AuthenticateUser/AuthUser.aspx?fid=0;1&tck=&&&lastm=20141001150602', "ASP.NET_SessionId=#{data.sid}"

  .then (res) ->

    eventValidation = /id="__EVENTVALIDATION".*/g.exec(res.body)[0]
    eventValidation = eventValidation.substr 30
    eventValidation = eventValidation.substr 0, eventValidation.length - 4

    viewState = /id="__VIEWSTATE".*/g.exec(res.body)[0]
    viewState = viewState.substr 24
    viewState = viewState.substr 0, viewState.length - 4

    postData2 =
      __EVENTVALIDATION: eventValidation
      __VIEWSTATE: viewState
      Fm_Action: '09'
      Frm_No: ''
      Frm_Type: ''
      TicketTextBox: ''
      TxtMiddle: '<r F51851="" F80351="810190498" F80401="dorosty" F83181="" F51701=""/>'

    postQ 'https://golestan.ut.ac.ir/Forms/AuthenticateUser/AuthUser.aspx?fid=0%3b1&tck=&&&lastm=20141001150602', postData2, "ASP.NET_SessionId=#{data.sid}; u=; su=; ft=; f=; lt=; seq="
    .then (res) ->

      savAut = /SavAut.*/g.exec(res.body)[0]
      savAut = savAut.split ','

      tck = savAut[savAut.length - 6]
      tck = tck.substr 1, tck.length - 2
      seq = savAut[savAut.length - 5]

      { sid: data.sid, tck, seq }

.then ({ sid, tck, seq }) ->

  getQ "https://golestan.ut.ac.ir/Forms/F0213_PROCESS_SYSMENU/F0213_01_PROCESS_SYSMENU_Dat.aspx?r=#{Math.random()}&fid=0;11130&b=&l=&tck=#{tck}&&lastm=20090829065642", "ASP.NET_SessionId=#{sid}; f=1; ft=0; lt=#{tck}; seq=#{seq}; stdno=; su=0; u=756524"
  
  .then (res) ->

    savAut = /SavAut.*/g.exec(res.body)[0]
    savAut = savAut.split ','

    lt = savAut[savAut.length - 7]
    lt = lt.substr 1, lt.length - 2
    tck = savAut[savAut.length - 6]
    tck = tck.substr 1, tck.length - 2
    seq = savAut[savAut.length - 5]

    { lt, tck, seq }

  .then ({ lt, tck, seq }) ->
    getQ "https://golestan.ut.ac.ir/Forms/F0202_PROCESS_REP_FILTER/F0202_01_PROCESS_REP_FILTER_DAT.ASPX?r=#{Math.random()}&fid=1;212&b=0&l=0&tck=#{tck}&isb=4&lastm=20130610102452", "ASP.NET_SessionId=#{sid}; f=11130; ft=0; lt=#{lt}; seq=#{seq}; stdno=; su=0; u=756524"

.then (res) ->

  result = ''

  xml = /<Root>.*<\/Root>/g.exec(res.body)[0]
  rowRegex = /<row.*?\/>/g
  while row = rowRegex.exec xml
    row = row[0]

    x = /C2=".*?"/g.exec(row)[0]
    result += x.substr 4, x.length - 5
    result += '\t'
    x = /C7=".*?"/g.exec(row)[0]
    result += x.substr 4, x.length - 5
    result += '\t'
    x = /C8=".*?"/g.exec(row)[0]
    result += x.substr 4, x.length - 5

    result += '\r\n'

    result = result.replace '&lt;BR&gt;', ' '
    result = result.replace '&lt;BR&gt;', ' '
    result = result.replace '&lt;BR&gt;', ' '
    result = result.replace '&lt;BR&gt;', ' '

    writeFileQ 'Results.txt', result

.then ->
  console.log 'Done. Check "Resutls.txt"'