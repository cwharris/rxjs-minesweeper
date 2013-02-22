# $.fn.longPressAsObservable = ->

# 	$this = $(this)

# 	$this.onAsObservable('click').selectMany (e) ->
# 		Rx.Observable.merge(
# 			Rx.Observable.interval(1000).take(1).select -> e
# 			$(document).onAsObservable('mouseup').selectMany -> Observable.empty()
# 			)

(->

	tapDelay = 200
	longPressDelay = 200

	$.fn.tapReleaseAsObservable = ->
		Rx.Observable.merge(
			$(this).onAsObservable('mouseup')
			$(this).onAsObservable('touchend')
		)

	tapRelease = $(document).tapReleaseAsObservable()

	$.fn.tapAsObservable = ->
		Rx.Observable.merge(
			$(this).onAsObservable('mousedown')
			$(this).onAsObservable('touchstart')
		)
			.doAction((e)-> e.preventDefault())
			.selectMany (e) ->
				tapRelease.select(->e).take(1).takeUntil Rx.Observable.interval(tapDelay).take(1)

	$.fn.longPressAsObservable = ->
		Rx.Observable.merge(
			$(this).onAsObservable('mousedown')
			$(this).onAsObservable('touchstart')
		)
			.selectMany (e) ->
				Rx.Observable.returnValue(e).delay(longPressDelay).takeUntil(tapRelease);

)()

makeMinefieldUnit = ->

	unit = {}

	friends = []

	unit.isBomb 	= new Rx.BehaviorSubject false
	unit.isCovered 	= new Rx.BehaviorSubject true
	unit.numBombs 	= new Rx.BehaviorSubject 0
	unit.flag 		= new Rx.BehaviorSubject 'none'

	unit.addFriend = (friend) ->
		friends.push friend
		friend.isBomb.skipWhile((x) -> not x).subscribe (isBomb) ->
			unit.numBombs.onNext unit.numBombs.value + if isBomb then 1 else -1

	unit.getFriends = () ->
		friends

	unit.nextFlag = () ->
		switch unit.flag.value
			when 'none'
				unit.flag.onNext 'certain'
				break
			when 'certain'
				unit.flag.onNext 'uncertain'
				break
			else
				unit.flag.onNext 'none'

	unit

makeMinefield = (width, height, numMinesRequested) ->

	minefield =
		width: 		width
		height: 	height
		numBombs: 	new Rx.BehaviorSubject numMinesRequested
		numFlags:	new Rx.BehaviorSubject 0
		units: 		[]
		solved:		new Rx.Subject

	reveals = new Rx.Subject

	minefield.getUnit = (x, y) ->
		# x -= minefield.width while x >= minefield.width
		# x += minefield.width while x < 0
		# y -= minefield.height while y >= minefield.height
		# y += minefield.height while y < 0
		return undefined if x < 0 or y < 0 or x >= minefield.width or y > minefield.height
		minefield.units[y * minefield.width + x]

	minefield.populateBombsWithFirstReveal = (unit, numMinesRequested) ->
		tempUnits = minefield.units.slice(0)
		index = tempUnits.indexOf(unit)
		tempUnits.splice index, 1

		for friend in unit.getFriends()
			index = tempUnits.indexOf(friend)
			tempUnits.splice index, 1		

		for i in [0...numMinesRequested]
			if tempUnits.length <= 0
				minefield.numBombs.onNext i
				break

			index = Math.floor(Math.random() * tempUnits.length)

			unit = tempUnits[index]
			tempUnits.splice index, 1

			unit.isBomb.onNext true

	for i in [0...width*height]
		(->
			unit = minefield.units[i] = makeMinefieldUnit()
			reveals = reveals.merge unit.isCovered.where((isCovered) -> !isCovered).select -> unit
			unit.flag
				.select((x) -> if x is 'certain' then 1 else -1)
				.skipWhile((x) -> x < 0)
				.distinctUntilChanged()
				.select((x) -> minefield.numFlags.value + x)
				.subscribe minefield.numFlags
		)()


	for x in [0...width]
		for y in [0...height]

			unit = minefield.getUnit x, y

			for xOffset in [-1..1]
				for yOffset in [-1..1]
					if xOffset is 0 and yOffset is 0
						continue

					friendUnit = minefield.getUnit x - xOffset, y - yOffset

					unit.addFriend friendUnit if friendUnit isnt undefined

	reveals.take(1).subscribe (unit) ->
		minefield.populateBombsWithFirstReveal unit, numMinesRequested

	minefield.solved = reveals.combineLatest(minefield.numBombs, (_, x) -> x)
		.where((numBombs) ->
			# numUncovered = (_.filter minefield.units, (unit) -> not unit.isCovered.value).length 
			# console.log numBombs, minefield.units.length - numUncovered
			# numBombs is minefield.units.length - numUncovered

			coveredUnits = _.filter minefield.units, (unit) -> unit.isCovered.value
			# console.log numBombs, coveredUnits
			numBombs is coveredUnits.length
		).take(1)

	minefield.failed = reveals
		# .doAction((x)-> console.log x)
		.where((x)->x.isBomb.value)
		.take(1)

	# reveals.where((unit) -> unit.isBomb.value).subscribe ->


	# 	a = _.any _.filter(minefield.units, (unit) -> unit.isCovered.value), (unit) ->

	# 		coveredFriends = _.filter unit.getFriends(), (friend) -> friend.isCovered.value

	# 		console.log coveredFriends.length, unit.numBombs.value

	# 		coveredFriends.length == unit.numBombs.value and unit.numBombs.value > 0


	# 	console.log a

	reveals.where((unit) -> unit.numBombs.value is 0 and not unit.isBomb.value).delay(25).subscribe (unit) ->
		for friend in unit.getFriends() when friend.isCovered.value
			friend.isCovered.onNext false

	minefield

makeMinefieldUnitView = (unit, x, y, size, spacing) ->

	dom = $ '<div class="minefield-unit">'
	domBombCount = $('<p class="bomb-count">').appendTo dom

	dom.tapAsObservable()
		.where(-> !unit.isCovered.value)
		 .select(-> _.filter unit.getFriends(), (friend) -> friend.flag.value != 'none' and friend.isCovered.value)
		.where((x) -> x.length == unit.numBombs.value)
		.take(1)
		.select(-> _.filter unit.getFriends(), (friend) -> friend.flag.value == 'none')
		# .select(-> unit.getFriends())
		.subscribe (friends) ->
			_.each friends, (friend) -> friend.isCovered.onNext false

	inputDisposable = new Rx.CompositeDisposable

	inputDisposable.add dom.tapAsObservable().where(-> unit.flag.value is 'none').take(1).subscribe ->
		console.log 'tap'
		# unit.isBomb.onNext true
		unit.isCovered.onNext false

	inputDisposable.add dom.longPressAsObservable().subscribe ->
		console.log 'long press'
		unit.nextFlag()

	comb = size.combineLatest spacing, (size, spacing) ->
		size: size
		spacing: spacing

	comb.subscribe (comb) ->
		dom.css
			position: 'absolute'
			left: x * (comb.size + comb.spacing)
			top: y * (comb.size + comb.spacing)
			width: comb.size
			height: comb.size

	unit.isBomb.subscribe (isBomb) -> dom.toggleClass 'bomb', isBomb
	unit.isCovered.where((x) -> !x).take(1).subscribe ->
		console.log 'dispose inputs'
		inputDisposable.dispose()
	unit.isCovered.subscribe (isCovered) -> dom.toggleClass 'covered', isCovered
	unit.numBombs.subscribe (numBombs) ->
		dom.toggleClass 'near-bomb', numBombs > 0
		domBombCount.html numBombs

	unit.flag.subscribe (flag) ->
		dom.toggleClass 'flag-none', flag == 'none'
		dom.toggleClass 'flag-certain', flag == 'certain'
		dom.toggleClass 'flag-uncertain', flag == 'uncertain'

	dom

makeMinefieldView = (minefield, mineSize, mineSpacing) ->

	dom = $ '<div class="minefield">'

	controller = {}

	for unit, i in minefield.units
		x = i % minefield.width
		y = Math.floor i / minefield.width

		dom.append makeMinefieldUnitView unit, x, y, mineSize, mineSpacing

	dom

$ ->
	width = 16
	height = 16
	size = new Rx.BehaviorSubject 40
	spacing = new Rx.BehaviorSubject 3

	minefield = makeMinefield width, height, 30
	minefieldView = makeMinefieldView minefield, size, spacing

	$('body').append minefieldView

	size.combineLatest(spacing, (size, spacing) -> size: size, spacing: spacing).subscribe (x) ->


		totalWidth = (x.size * width) + (x.spacing * width - 1)
		totalHeight = (x.size * height) + (x.spacing * height - 1)

		console.log x.size, x.spacing, totalWidth, totalHeight

		minefieldView.css
			width: totalWidth
			height: totalHeight

	holder = $('<div>').css('position': 'fixed').appendTo 'body'

	holder.append domBombCount = $ '<div class="bomb-count">'

	numRemaining = minefield.numBombs.combineLatest minefield.numFlags, (numBombs, numFlags) -> numBombs - numFlags

	numRemaining.subscribe (numRemaining) ->
		domBombCount.html numRemaining

	minefield.failed.takeUntil(minefield.solved).subscribe ->
		alert 'FAILED'
		bombs = _.filter minefield.units, (unit) -> unit.isBomb.value
		Rx.Observable.interval(10).take(bombs.length).select((i)->bombs[i]).subscribe (unit) ->
			unit.isCovered.onNext false

	minefield.solved.takeUntil(minefield.failed).subscribe ->
		alert 'SOLVED'
		bombs = _.filter minefield.units, (unit) -> unit.isBomb.value
		Rx.Observable.interval(10).take(bombs.length).select((i)->bombs[i]).subscribe ->
			bomb.isCovered.onNext false
		# $('body').remove()

	# holder.append sizeInput = $ '<input type="text">'
	# holder.append spacingInput = $ '<input type="text">'

	# sizeInput.onAsObservable('keyup')
	# 	.select((x) -> $(x.target).val())
	# 	.select((x) -> parseFloat x, 10)
	# 	.subscribe (x) ->
	# 		console.log x
	# 		size.onNext x

	# spacingInput.onAsObservable('keyup')
	# 	.select((x) -> $(x.target).val())
	# 	.select((x) -> parseFloat x, 10)
	# 	.subscribe (x) ->
	# 		console.log x
	# 		spacing.onNext x
