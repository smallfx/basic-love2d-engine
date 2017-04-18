--import table

function table.clone(org)
  return {table.unpack(org)}
end

function sign(num)
	return num / math.abs(num)
end

love.graphics.setDefaultFilter('nearest', 'nearest')

local Util = {
	pointInBox = function(pt, bx)
		return (pt.x > bx.x) and
			   (pt.x < (bx.x + bx.w)) and
			   (pt.y > bx.yr) and
			   (pt.y < (bx.y + bx.h))
	end,
	aabb = function(one, two)
		local oneL = one.x
		local oneR = one.x + one.width
		local twoL = two.x
		local twoR = two.x + two.width
		local oneT = one.y
		local oneB = one.y + one.height
		local twoT = two.y
		local twoB = two.y + two.height

		return (((oneL > twoL) and (oneL < twoR)) or
				((oneR > twoL) and (oneR < twoR))) and
				(((oneT > twoT) and (oneT < twoB)) or
				((oneB > twoT) and (oneB < twoB)))

	end
}

local Engine = {
	totalTime = 0,
	accumulator = 0,
	timestep = 1 / 60,
	zoomFactor = 2,
	camera = { x = 0, y = 0, easing = 0, target = nil },
	actors = {},
	graphicCache = {},
	inputState = {
		left = { pressed = false, justPressed = false, justReleased = false },
		right = { pressed = false, justPressed = false, justReleased = false },
		button = { pressed = false, justPressed = false, justReleased = false }
	},
	touches = {},
	screenButtonBoxes = {
		left = { x = 0, y = 600, w = 150, h = 150 },
		right = { x = 150, y = 600, w = 150, h = 150 },
		button = { x = 300, y = 600, w = 150, h = 150 }
	},
	init = function(self)
		function love.touchpressed(id, x, y, dx, dy, pressure)
			touches[id] = { x = x, y = y, justPressed = true }
		end

		function love.touchmoved(id, x, y, dx, dy, pressure)
			touches[id] = { x = x, y = y, justPressed = false }
		end

		function love.touchreleased(id, x, y, dx, dy, pressure)
			touches[id] = nil
		end

		function love.update(dt)
			self.totalTime = self.totalTime + dt
			self.accumulator = self.accumulator + dt
			if (self.accumulator >= self.timestep) then
				local iterations = math.floor(self.accumulator / self.timestep)
				self.accumulator = self.accumulator % self.timestep
				for i = 1, iterations do
					self:fixedUpdate()
				end
			end
		end

		function love.draw()
			for y = 1, self.map.height do
				for x = 1, self.map.width do
					local tileframe = self.map.mapdata[y][x]
					print(tileframe)
					if tileframe > 0 then
						love.graphics.draw(self.map.tileset.image,
										   self.map.tileset.frames[self.map.mapdata[y][x] + 1],
										   math.floor(((x - 1) * 16) - self.camera.x) * self.zoomFactor,
										   math.floor(((y - 1) * 16) - self.camera.y) * self.zoomFactor,
										   0,
										   self.zoomFactor)
					end
				end
			end
			for i = 1, table.getn(self.actors) do
				local actor = self.actors[i]
				local displayedFrame = 1
				if actor.activeAnimation then
					local animation = actor.animations[actor.activeAnimation]
					local frameCount = table.getn(animation.frames)
					local animationSeconds = ((actor.timeCreated + actor.elapsedSinceCreated) - actor.animationStart)
					displayedFrame = 1 + math.floor((animationSeconds * animation.fps) % frameCount)
				end
				if (actor.graphic) then
					love.graphics.draw(actor.graphic.image,
									   actor.graphic.frames[displayedFrame],
									   math.floor(actor.x - self.camera.x) * self.zoomFactor,
									   math.floor(actor.y - self.camera.y) * self.zoomFactor,
									   0,
									   self.zoomFactor)
				end
			end
		end
	end,
	makeGraphic = function(self, imageFilename, frameWidth, frameHeight)
		if not frameWidth then frameWidth = 0 end
		if not frameHeight then frameHeight = 0 end
		if ((not imageFilename) or (not love.filesystem.exists(imageFilename))) then
			imageFilename = 'missing_graphic.png'
		end

		local cacheKey = imageFilename .. '_' .. frameWidth .. 'x' .. frameHeight
		if self.graphicCache[cacheKey] then
			return self.graphicCache[cacheKey]
		end

		local loadedImage = love.graphics.newImage(imageFilename)
		local imageWidth, imageHeight = loadedImage:getDimensions()
		frameWidth = math.min(imageWidth, frameWidth)
		frameHeight = math.min(imageHeight, frameHeight)

		local graphic = {
			image = loadedImage,
			frameWidth = frameWidth,
			frameHeight = frameWidth,
			width = imageWidth,
			height = imageHeight,
			frames = {},
			frameCount = 0
		};

		if (frameWidth > 0) and
		   (frameHeight > 0) then
			local gridWidth = math.floor(imageWidth / frameWidth)
			local gridHeight = math.floor(imageHeight / frameHeight)
			graphic.frameCount = gridWidth * gridHeight
			for y = 0, gridHeight do
				for x = 0, gridWidth do
					local frameNum = 1 + x + (y * gridWidth)
					graphic.frames[frameNum] = love.graphics.newQuad(
						x * frameWidth,
						y * frameHeight,
						frameWidth,
						frameHeight,
						imageWidth,
						imageHeight
					)
				end
			end
		else
			graphic.frames[1] = love.graphics.newQuad(
				0,
				0,
				imageWidth,
				imageHeight,
				imageWidth,
				imageHeight
			)
		end

		self.graphicCache[cacheKey] = graphic
		return graphic
	end,
	fixedUpdate = function(self)
		for i = 1, table.getn(self.actors) do
			local actor = self.actors[i]
			actor.elapsedSinceCreated = actor.elapsedSinceCreated + self.timestep
			if (actor.behavior) then actor:behavior(self) end
			if (math.abs(actor.acceleration.x) > 0) then
				actor.velocity.x = math.max(actor.maxVelocity.x, actor.velocity.x + actor.acceleration.x)
			elseif (actor.velocity.x > 0) then
				local vsign = sign(actor.velocity.x)
				actor.velocity.x = math.max(0, math.abs(actor.velocity.x) - actor.deceleration.x) * vsign
			end
			if (math.abs(actor.acceleration.y) > 0) then
				actor.velocity.y = math.max(actor.maxVelocity.y, actor.velocity.y + actor.acceleration.y)
			elseif (actor.velocity.y > 0) then
				local vsign = sign(actor.velocity.y)
				actor.velocity.y = math.max(0, math.abs(actor.velocity.y) - actor.deceleration.y) * vsign
			end
			actor.x = actor.x + actor.velocity.x
			actor.y = actor.y + actor.velocity.y
		end
	end,
	makeActor = function(self, x, y, w, h, gfx)
		return {
			x = x or 0,
			y = y or 0,
			width = w or 0,
			height = h or 0,
			graphic = gfx,
			velocity = {
				x = 0,
				y = 0
			},
			maxVelocity = {
				x = 0,
				y = 0
			},
			acceleration = {
				x = 0,
				y = 0
			},
			deceleration = {
				x = 0,
				y = 0
			},
			animations = {},
			activeAnimation = nil,
			animationStart = 0,
			timeCreated = self.totalTime,
			elapsedSinceCreated = 0
		}
	end,
	makeAnimation = function(self, frames, fps)
		return {
			frames = frames,
			fps = fps
		}
	end
}

function Engine:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end


function playAnimation(actor, animationName, restart)
	if(restart or (activeAnimation ~= animationName)) then
		actor.activeAnimation = animationName
		actor.animationStart = actor.timeCreated + actor.elapsedSinceCreated
	end
end

local eng = Engine:new()
local newGfx = eng:makeGraphic('hero_sprites.png', 16 ,16)
local newActor = eng:makeActor(10, 10, 16, 16, newGfx)
newActor.animations['walk'] = eng:makeAnimation({1, 2}, 1)
newActor.behavior = function(self, engine)
	self.velocity.y = 0.5
end
playAnimation(newActor, 'walk')
newActor.velocity.x = 0.2
eng.actors = { newActor }

local tileset = eng:makeGraphic('basictiles.png', 16 ,16)
local mapdata = {
	{1,1,1,1,1},
	{1,0,0,0,1},
	{1,0,0,0,1},
	{1,0,0,0,1},
	{1,1,1,1,1}
}
eng.map = { tileset = tileset, mapdata = mapdata, width = 5, height = 5 }

eng:init()

