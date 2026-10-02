local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Blueprint Gallery GRID",
		desc = "While placing a blueprint (Alt+B), your blueprints replace the build grid: same tabs (Economy/Combat/Utility/Build) and same hotkeys. Drag a thumbnail to arrange it, right-click to change its category, Shift to go back. Follows the game language.",
		author = "Boniito",
		date = "2026-09-27",
		license = "GNU GPL, v2 or later",
		layer = -1, -- avant la grille (0), le widget molette de Vvsod (0) et Blueprint (1)
		enabled = true,
		handler = true, -- acces a widgetHandler.actionHandler, pour trouver les fonctions du widget officiel et de la grille
	}
end

--[[
Galerie de blueprints. Conception : CONCEPTION-galerie-blueprints.md (depot BAR-Calculateur), revision 3.

Le widget officiel « Blueprint » (cmd_blueprint.lua) garde seul la liste, la pose et la sauvegarde. La galerie lit
sa liste en memoire et sa fonction de selection par debug.getupvalue sur la fonction de l'action « blueprint_next »,
recherchee a chaque usage. Elle ne desactive, ne recharge ni n'ecrit blueprints.json : elle modifie seulement le
champ name des blueprints en memoire (categorie et case), que le widget officiel sauvegarde a sa fermeture.

Mode grille (normal) : pendant la pose, la galerie se dessine par-dessus la grille (« Grid menu ») dans ses cases
et ses onglets, et reprend ses touches (actions gridmenu_*). La grille est rendue aveugle a la souris par une
enveloppe sur backgroundRect.contains, sure par construction (battement de coeur). Structure de la grille relevee
dans le moteur (spring-headless, bac a sable, 2026-09-27) : cellRects, catRects, backgroundRect, keyLayout.
Mode panneau (repli, v1) : si la grille est cachee ou introuvable, panneau flottant au-dessus de sa place.

Nom d'un blueprint : « [eco 5] reste » = categorie + case (12 par page), « [eco] reste » = categorie seule,
sinon categorie automatique : Build si une usine ou seulement des nanos, sinon onglet de la grille
(customParams.unitgroup) du batiment qui pese le plus (metal + energie/60), nanos ignores.

Mesure (tools/mesure_blueprints.py) : lignes « [Galerie] ... » et « [Editeur] ... » dans l'infolog, plus le verrou
et le journal de l'editeur hors partie : actifs SEULEMENT si LuaUI/Config/galerie_mesure.flag existe (installation
du joueur qui mesure). Version publique : rien d'ecrit sur disque, pas de lignes de mesure dans la console.
]]

local CMD_BLUEPRINT_PLACE = (GameCMD and GameCMD.BLUEPRINT_PLACE) or 18200
local BP_WIDGET = "Blueprint"
local GRID_WIDGET = "Grid menu"
local KEY_ESCAPE = (KEYSYMS and KEYSYMS.ESCAPE) or 27
local CELLS = 12
local LOCK_FILE = "LuaUI/Config/galerie_partie.lock"
local JOURNAL_FILE = "LuaUI/Config/galerie_disposition_voulue.json"
local BLUEPRINT_FILE = "LuaUI/Config/blueprints.json"
local MEASURE_FLAG = "LuaUI/Config/galerie_mesure.flag"
local WIDGET_NAME = "Blueprint Gallery GRID"

local CATS = { "eco", "combat", "util", "prod" } -- ordre des onglets de la grille
local VALID_CAT = { eco = true, combat = true, util = true, prod = true }
local I18N_KEY = {
	eco = "ui.buildMenu.category_econ",
	combat = "ui.buildMenu.category_combat",
	util = "ui.buildMenu.category_utility",
	prod = "ui.buildMenu.category_production",
}
local FALLBACK_LABEL = { all = "All", eco = "Economy", combat = "Combat", util = "Utility", prod = "Build" }
local PANEL_TABS = { "all", "eco", "combat", "util", "prod" }
local COLOR = {
	eco = { 0.95, 0.80, 0.25 },
	combat = { 0.95, 0.35, 0.30 },
	util = { 0.35, 0.75, 0.95 },
	prod = { 0.55, 0.90, 0.45 },
}
-- meme table que luaui/configs/gridmenu_config.lua (categoryGroupMapping), le reste va en Utility
local GROUP_CAT = {
	energy = "eco", metal = "eco",
	builder = "prod", buildert2 = "prod", buildert3 = "prod", buildert4 = "prod",
	util = "util",
	weapon = "combat", explo = "combat", weaponaa = "combat", weaponsub = "combat", aa = "combat",
	emp = "combat", sub = "combat", nuke = "combat", antinuke = "combat",
}

local WHEEL_RATE_LIMIT = 1 / 15
local HEARTBEAT_S = 0.25 -- la grille redevient normale si la galerie ne bat plus depuis 0,25 s
local LOCK_EVERY_S = 20
local DRAG_MIN_PX = 6
--------------------------------------------------------------------------------
-- Langue : suit celle du jeu (Spring.GetConfigString("language")), change en direct (LanguageChanged).
-- Langues du jeu sans traduction ici (cs, hr, lt...) : anglais.
--------------------------------------------------------------------------------

local STRINGS = {
	en = {
		noDebug = "debug.getupvalue missing",
		noWidget = 'widget "Blueprint" not found or disabled',
		noVars = 'internals of the "Blueprint" widget not found (game update?)',
		unavailable = "unavailable: %s — the game works as without the gallery.",
		gridMissing = "build grid not found: falling back to the panel (game update?)",
		nativeBroken = "grid drawing unavailable, simplified drawing: %s",
		optName = "Mouse wheel while placing",
		optDesc = "What the mouse wheel does while placing a blueprint. Ctrl+wheel always switches tabs.",
		optSelect = "Select blueprint (Alt+wheel: rotate)",
		optRotate = "Rotate blueprint (Alt+wheel: select)",
		tooltip = "#%d  ·  %d units  ·  %s\nClick: select  ·  drag: arrange  ·  right-click: category",
		hintSelect = "Wheel: select  ·  Ctrl+wheel: tab  ·  Alt+wheel: rotate  ·  Right-click: category",
		hintRotate = "Wheel: rotate  ·  Ctrl+wheel: tab  ·  Alt+wheel: select  ·  Right-click: category",
		empty = "No blueprint in this tab",
		all = "All",
		page = "Page",
	},
	fr = {
		noDebug = "debug.getupvalue absent",
		noWidget = "widget « Blueprint » introuvable ou désactivé",
		noVars = "variables du widget « Blueprint » introuvables (mise à jour du jeu ?)",
		unavailable = "indisponible : %s — le jeu fonctionne comme sans la galerie.",
		gridMissing = "grille introuvable : repli sur le panneau (mise à jour du jeu ?)",
		nativeBroken = "dessin de la grille indisponible, dessin simplifié : %s",
		optName = "Molette pendant la pose",
		optDesc = "Ce que fait la molette pendant la pose d'un blueprint. Ctrl+molette change toujours d'onglet.",
		optSelect = "Choisir le blueprint (Alt+molette : tourner)",
		optRotate = "Tourner le blueprint (Alt+molette : choisir)",
		tooltip = "#%d  ·  %d unités  ·  %s\nClic : choisir  ·  glisser : ranger  ·  clic droit : catégorie",
		hintSelect = "Molette : choisir  ·  Ctrl+molette : onglet  ·  Alt+molette : tourner  ·  Clic droit : catégorie",
		hintRotate = "Molette : tourner  ·  Ctrl+molette : onglet  ·  Alt+molette : choisir  ·  Clic droit : catégorie",
		empty = "Aucun blueprint dans cet onglet",
		all = "Tous",
		page = "Page",
	},
	de = {
		noDebug = "debug.getupvalue fehlt",
		noWidget = 'Widget "Blueprint" nicht gefunden oder deaktiviert',
		noVars = 'Interna des Widgets "Blueprint" nicht gefunden (Spiel-Update?)',
		unavailable = "nicht verfügbar: %s — das Spiel läuft wie ohne die Galerie.",
		gridMissing = "Bauraster nicht gefunden: Rückfall auf das Panel (Spiel-Update?)",
		nativeBroken = "Raster-Darstellung nicht verfügbar, vereinfachte Darstellung: %s",
		optName = "Mausrad beim Platzieren",
		optDesc = "Was das Mausrad beim Platzieren eines Blueprints tut. Strg+Mausrad wechselt immer den Reiter.",
		optSelect = "Blueprint auswählen (Alt+Mausrad: drehen)",
		optRotate = "Blueprint drehen (Alt+Mausrad: auswählen)",
		tooltip = "#%d  ·  %d Einheiten  ·  %s\nKlick: auswählen  ·  Ziehen: anordnen  ·  Rechtsklick: Kategorie",
		hintSelect = "Mausrad: auswählen  ·  Strg+Mausrad: Reiter  ·  Alt+Mausrad: drehen  ·  Rechtsklick: Kategorie",
		hintRotate = "Mausrad: drehen  ·  Strg+Mausrad: Reiter  ·  Alt+Mausrad: auswählen  ·  Rechtsklick: Kategorie",
		empty = "Kein Blueprint in diesem Reiter",
		all = "Alle",
		page = "Seite",
	},
	es = {
		noDebug = "falta debug.getupvalue",
		noWidget = 'widget "Blueprint" no encontrado o desactivado',
		noVars = 'datos internos del widget "Blueprint" no encontrados (¿actualización del juego?)',
		unavailable = "no disponible: %s — el juego funciona como sin la galería.",
		gridMissing = "cuadrícula de construcción no encontrada: se usa el panel (¿actualización del juego?)",
		nativeBroken = "dibujo de la cuadrícula no disponible, dibujo simplificado: %s",
		optName = "Rueda del ratón al colocar",
		optDesc = "Lo que hace la rueda al colocar un blueprint. Ctrl+rueda siempre cambia de pestaña.",
		optSelect = "Elegir el blueprint (Alt+rueda: girar)",
		optRotate = "Girar el blueprint (Alt+rueda: elegir)",
		tooltip = "#%d  ·  %d unidades  ·  %s\nClic: elegir  ·  arrastrar: ordenar  ·  clic derecho: categoría",
		hintSelect = "Rueda: elegir  ·  Ctrl+rueda: pestaña  ·  Alt+rueda: girar  ·  Clic derecho: categoría",
		hintRotate = "Rueda: girar  ·  Ctrl+rueda: pestaña  ·  Alt+rueda: elegir  ·  Clic derecho: categoría",
		empty = "Ningún blueprint en esta pestaña",
		all = "Todos",
		page = "Página",
	},
	it = {
		noDebug = "debug.getupvalue mancante",
		noWidget = 'widget "Blueprint" non trovato o disattivato',
		noVars = 'dati interni del widget "Blueprint" non trovati (aggiornamento del gioco?)',
		unavailable = "non disponibile: %s — il gioco funziona come senza la galleria.",
		gridMissing = "griglia di costruzione non trovata: si usa il pannello (aggiornamento del gioco?)",
		nativeBroken = "disegno della griglia non disponibile, disegno semplificato: %s",
		optName = "Rotellina durante il posizionamento",
		optDesc = "Cosa fa la rotellina mentre si posiziona un blueprint. Ctrl+rotellina cambia sempre scheda.",
		optSelect = "Scegliere il blueprint (Alt+rotellina: ruotare)",
		optRotate = "Ruotare il blueprint (Alt+rotellina: scegliere)",
		tooltip = "#%d  ·  %d unità  ·  %s\nClic: scegliere  ·  trascinare: ordinare  ·  clic destro: categoria",
		hintSelect = "Rotellina: scegliere  ·  Ctrl+rotellina: scheda  ·  Alt+rotellina: ruotare  ·  Clic destro: categoria",
		hintRotate = "Rotellina: ruotare  ·  Ctrl+rotellina: scheda  ·  Alt+rotellina: scegliere  ·  Clic destro: categoria",
		empty = "Nessun blueprint in questa scheda",
		all = "Tutti",
		page = "Pagina",
	},
	ru = {
		noDebug = "нет debug.getupvalue",
		noWidget = "виджет «Blueprint» не найден или отключён",
		noVars = "внутренние данные виджета «Blueprint» не найдены (обновление игры?)",
		unavailable = "недоступно: %s — игра работает как без галереи.",
		gridMissing = "сетка строительства не найдена: используется панель (обновление игры?)",
		nativeBroken = "отрисовка сетки недоступна, упрощённая отрисовка: %s",
		optName = "Колесо мыши при размещении",
		optDesc = "Что делает колесо мыши при размещении чертежа. Ctrl+колесо всегда переключает вкладку.",
		optSelect = "Выбор чертежа (Alt+колесо: поворот)",
		optRotate = "Поворот чертежа (Alt+колесо: выбор)",
		tooltip = "#%d  ·  единиц: %d  ·  %s\nЩелчок: выбрать  ·  перетащить: упорядочить  ·  ПКМ: категория",
		hintSelect = "Колесо: выбор  ·  Ctrl+колесо: вкладка  ·  Alt+колесо: поворот  ·  ПКМ: категория",
		hintRotate = "Колесо: поворот  ·  Ctrl+колесо: вкладка  ·  Alt+колесо: выбор  ·  ПКМ: категория",
		empty = "Нет чертежей в этой вкладке",
		all = "Все",
		page = "Стр.",
	},
	zh = {
		noDebug = "缺少 debug.getupvalue",
		noWidget = "未找到或已禁用 “Blueprint” 小部件",
		noVars = "未找到 “Blueprint” 小部件的内部数据（游戏更新？）",
		unavailable = "不可用：%s —— 游戏照常运行，不受图库影响。",
		gridMissing = "未找到建造网格：改用面板显示（游戏更新？）",
		nativeBroken = "网格绘制不可用，改用简化绘制：%s",
		optName = "放置时的鼠标滚轮",
		optDesc = "放置蓝图时鼠标滚轮的作用。Ctrl+滚轮始终切换标签页。",
		optSelect = "选择蓝图（Alt+滚轮：旋转）",
		optRotate = "旋转蓝图（Alt+滚轮：选择）",
		tooltip = "#%d  ·  %d 个单位  ·  %s\n点击：选择  ·  拖动：整理  ·  右键：分类",
		hintSelect = "滚轮：选择  ·  Ctrl+滚轮：标签页  ·  Alt+滚轮：旋转  ·  右键：分类",
		hintRotate = "滚轮：旋转  ·  Ctrl+滚轮：标签页  ·  Alt+滚轮：选择  ·  右键：分类",
		empty = "此标签页中没有蓝图",
		all = "全部",
		page = "页",
	},
}

local lang = "en"

local function detectLanguage()
	local l = Spring.GetConfigString and Spring.GetConfigString("language", "en") or "en"
	l = type(l) == "string" and l:lower():sub(1, 2) or "en"
	lang = STRINGS[l] and l or "en"
	return lang
end

-- texte traduit ; une cle absente d'une langue retombe sur l'anglais
local function tr(key, ...)
	local s = (STRINGS[lang] and STRINGS[lang][key]) or STRINGS.en[key] or key
	if select("#", ...) > 0 then
		return string.format(s, ...)
	end
	return s
end

local spGetActiveCommand = Spring.GetActiveCommand
local spGetModKeyState = Spring.GetModKeyState
local spGetMouseState = Spring.GetMouseState
local spGetTimer = Spring.GetTimer
local spGetTimerMicros = Spring.GetTimerMicros -- GetTimer n'a que la milliseconde : trop grossier pour une image
local spDiffTimers = Spring.DiffTimers
local Echo = Spring.Echo
local MEASURE = false -- lu a l'initialisation (fichier-marqueur)

-- lignes de mesure : seulement chez le joueur qui mesure (infolog lu par tools/mesure_blueprints.py)
local function mEcho(s)
	if MEASURE then
		Echo(s)
	end
end

-- message pour le joueur, traduit
local function uEcho(s)
	Echo((MEASURE and "[Galerie] " or "[Blueprint Gallery GRID] ") .. s)
end

-- evenement important : traduit pour le joueur ; chez le joueur qui mesure, toujours le texte francais fixe que
-- tools/mesure_blueprints.py reconnait, quelle que soit la langue du jeu
local function eventEcho(fixedFr, key, ...)
	if MEASURE then
		Echo("[Galerie] " .. fixedFr)
	else
		uEcho(tr(key, ...))
	end
end
local mathFloor, mathMax, mathMin, mathCeil = math.floor, math.max, math.min, math.ceil

--------------------------------------------------------------------------------
-- Introspection (verifiee dans le moteur : callins enveloppes 2 fois, profileur -> SafeWrap -> callin)
--------------------------------------------------------------------------------

local function upvalue(fn, name)
	if type(fn) ~= "function" or not debug or not debug.getupvalue then
		return nil
	end
	local i = 1
	while true do
		local n, v = debug.getupvalue(fn, i)
		if n == nil then
			return nil
		end
		if n == name then
			return v
		end
		i = i + 1
	end
end

-- recherche en largeur ; releves moteur : 3 niveaux au plus, marge d'un niveau
local function upvalueDeep(fn, name, maxDepth)
	if type(fn) ~= "function" or not debug or not debug.getupvalue then
		return nil
	end
	local level, seen = { fn }, { [fn] = true }
	for _ = 1, (maxDepth or 3) + 1 do
		local nextLevel = {}
		for _, f in ipairs(level) do
			local i = 1
			while true do
				local n, v = debug.getupvalue(f, i)
				if n == nil then
					break
				end
				if n == name then
					return v
				end
				if type(v) == "function" and not seen[v] then
					seen[v] = true
					nextLevel[#nextLevel + 1] = v
				end
				i = i + 1
			end
		end
		level = nextLevel
	end
	return nil
end

local function actionOf(cmd, widgetName)
	local ah = widgetHandler and widgetHandler.actionHandler
	local list = ah and ah.keyPressActions and ah.keyPressActions[cmd]
	if not list then
		return nil
	end
	for _, ci in ipairs(list) do
		local w = ci[1]
		if w and w.whInfo and w.whInfo.name == widgetName then
			return ci[2], w
		end
	end
	return nil
end

---@return table|nil hook, string|nil reason
local function hook()
	if not (debug and debug.getupvalue) then
		return nil, tr("noDebug")
	end
	local nextFn, bpWidget = actionOf("blueprint_next", BP_WIDGET)
	if not nextFn then
		return nil, tr("noWidget")
	end
	local list = upvalue(nextFn, "blueprints")
	local setSel = upvalue(nextFn, "setSelectedBlueprintIndex")
	if type(list) ~= "table" or type(setSel) ~= "function" then
		return nil, tr("noVars")
	end
	local sounds = upvalue(nextFn, "sounds")
	local save = bpWidget and upvalueDeep(rawget(bpWidget, "Shutdown") or bpWidget.Shutdown, "saveBlueprintsToFile")
	local hidden = save and upvalue(save, "filteredOutSerializedBlueprints")
	return {
		list = list,
		setSel = setSel,
		facingFn = (actionOf("buildfacing", BP_WIDGET)),
		sound = type(sounds) == "table" and sounds.selectBlueprint or nil,
		hidden = type(hidden) == "table" and #hidden or 0,
		hiddenList = type(hidden) == "table" and hidden or nil, -- forme serialisee, sauvegardee telle quelle par le jeu
	}
end

local function selectedIndex(hk)
	return upvalue(hk.setSel, "selectedBlueprintIndex")
end

local function catLabel(c)
	if c ~= "all" and BAR and BAR.I18N then
		local ok, s = pcall(BAR.I18N, I18N_KEY[c])
		if ok and type(s) == "string" and s ~= "" and s ~= I18N_KEY[c] then
			return s
		end
	end
	if c == "all" then
		return tr("all")
	end
	return FALLBACK_LABEL[c]
end

---@return table|nil grid
-- fonctions de dessin de la grille (releve moteur 2026-09-27 : drawBuildMenu et drawBuildMenuBg au niveau 3 depuis
-- son DrawScreen enveloppe ; drawCategories, drawBackButtons, drawGrid, font2 au niveau 1 depuis drawBuildMenu ;
-- backRect, nextPageRect, currentCategoryRect au niveau 2 ; drawButton, drawButtonHotkey au niveau 1 depuis
-- drawCategories ; UiUnit, RectRound et les tailles au niveau 1 depuis drawCell). La galerie dessine avec elles pour
-- avoir l'aspect exact de la grille ; s'il en manque une, elle garde son propre dessin.
local function nativeHook(gw, bm)
	local ds = gw and (rawget(gw, "DrawScreen") or gw.DrawScreen)
	local dbm = upvalueDeep(ds, "drawBuildMenu", 4)
	if type(dbm) ~= "function" then
		return nil
	end
	local n = {
		bg = upvalueDeep(ds, "drawBuildMenuBg", 4),
		drawBack = upvalueDeep(dbm, "drawBackButtons", 3),
		cats = upvalueDeep(dbm, "drawCategories", 3),
		font = upvalueDeep(dbm, "font2", 3),
		backRect = upvalueDeep(dbm, "backRect", 3),
		nextRect = upvalueDeep(dbm, "nextPageRect", 3),
		curRect = upvalueDeep(dbm, "currentCategoryRect", 3),
		catFont = upvalueDeep(dbm, "categoryFontSize", 3),
		pageFont = upvalueDeep(dbm, "pageFontSize", 3),
		bgpadding = upvalueDeep(dbm, "bgpadding", 3),
		cell = upvalueDeep(dbm, "drawCell", 3),
		nextKey = upvalueDeep(bm.reloadBindings, "nextPageKey", 3),
	}
	n.button = upvalueDeep(n.cats, "drawButton", 3)
	n.hotkey = upvalueDeep(n.cats, "drawButtonHotkey", 3)
	for _, k in ipairs({ "UiUnit", "RectRound", "cellPadding", "iconPadding", "cornerSize", "priceFontSize", "cellInnerSize", "defaultCellZoom" }) do
		n[k] = upvalue(n.cell, k)
	end
	for _, k in ipairs({ "bg", "drawBack", "cell", "button", "hotkey", "UiUnit", "RectRound" }) do
		if type(n[k]) ~= "function" then
			return nil
		end
	end
	for _, k in ipairs({ "backRect", "nextRect", "curRect" }) do
		if type(n[k]) ~= "table" then
			return nil
		end
	end
	for _, k in ipairs({ "catFont", "pageFont", "bgpadding", "cellPadding", "iconPadding", "cornerSize", "priceFontSize", "cellInnerSize", "defaultCellZoom" }) do
		if type(n[k]) ~= "number" then
			return nil
		end
	end
	if not n.font then
		return nil
	end
	return n
end

local function gridHook()
	local keyFn, gw = actionOf("gridmenu_key", GRID_WIDGET)
	local catFn = actionOf("gridmenu_category", GRID_WIDGET)
	local bm = WG.buildmenu
	if not (keyFn and catFn and bm and bm.getSize and bm.reloadBindings and bm.getIsShowing) then
		return nil
	end
	local g = {
		cellRects = upvalueDeep(keyFn, "cellRects"),
		catRects = upvalueDeep(catFn, "catRects"),
		bg = upvalueDeep(bm.getSize, "backgroundRect"),
		keyLayout = upvalueDeep(bm.reloadBindings, "keyLayout"),
		keyConfig = upvalueDeep(bm.reloadBindings, "keyConfig"),
		layout = upvalueDeep(bm.reloadBindings, "currentLayout"),
		isShowing = bm.getIsShowing,
	}
	if type(g.cellRects) ~= "table" or #g.cellRects < CELLS or type(g.catRects) ~= "table" then
		return nil
	end
	if type(g.bg) ~= "table" or type(g.bg.contains) ~= "function" or type(g.keyLayout) ~= "table" then
		return nil
	end
	g.cat = {}
	for _, c in ipairs(CATS) do
		local r = g.catRects[catLabel(c)] or g.catRects[FALLBACK_LABEL[c]]
		if type(r) ~= "table" then
			return nil
		end
		g.cat[c] = r
	end
	g.native = nativeHook(gw, bm)
	return g
end

local function sanitizeKey(g, key)
	if not key or key == "" then
		return ""
	end
	if g.keyConfig and g.keyConfig.sanitizeKey then
		local ok, s = pcall(g.keyConfig.sanitizeKey, key, g.layout)
		if ok and type(s) == "string" then
			return s
		end
	end
	return (key:gsub("^Any%+", ""):gsub("^sc_", ""):upper())
end

--------------------------------------------------------------------------------
-- Noms : categorie et case
--------------------------------------------------------------------------------

local catCache = setmetatable({}, { __mode = "k" }) -- vide a chaque Update : le nom peut changer

---@return string|nil cat, number|nil slot, string rest
local function parseName(bp)
	local n = type(bp.name) == "string" and bp.name or ""
	local cat, slot, rest = n:match("^%[(%l+) (%d+)%] (.*)$")
	if cat and VALID_CAT[cat] then
		local s = tonumber(slot)
		if s and s >= 1 then
			return cat, s, rest
		end
	end
	cat, rest = n:match("^%[(%l+)%] (.*)$")
	if cat and VALID_CAT[cat] then
		return cat, nil, rest
	end
	return nil, nil, n
end

local function setName(bp, cat, slot)
	local _, _, rest = parseName(bp)
	if cat then
		bp.name = "[" .. cat .. (slot and (" " .. slot) or "") .. "] " .. rest
	else
		bp.name = rest
	end
	catCache[bp] = nil
end

local function unitCategory(ud)
	return GROUP_CAT[ud.customParams and ud.customParams.unitgroup] or "util"
end

local function isNano(ud)
	return ud.isBuilder and not ud.canMove and not ud.isFactory
end

local function autoCategory(bp)
	local weight, nanoWeight = {}, {}
	for _, u in ipairs(bp.units or {}) do
		local ud = u.unitDefID and UnitDefs[u.unitDefID]
		if ud then
			if ud.isFactory then
				return "prod"
			end
			local t = isNano(ud) and nanoWeight or weight
			local c = unitCategory(ud)
			t[c] = (t[c] or 0) + (ud.metalCost or 0) + (ud.energyCost or 0) / 60 -- cout habituel du jeu
		end
	end
	if next(weight) == nil then
		weight = nanoWeight
	end
	local best, bestW = "util", -1
	for _, c in ipairs(CATS) do
		if (weight[c] or 0) > bestW then
			best, bestW = c, weight[c] or 0
		end
	end
	return best
end

local function category(bp)
	local c = catCache[bp]
	if not c then
		c = (parseName(bp)) or autoCategory(bp)
		catCache[bp] = c
	end
	return c
end

--------------------------------------------------------------------------------
-- Etat
--------------------------------------------------------------------------------

local h = nil -- branchement sur « Blueprint » (refait a chaque usage)
local grid = nil -- branchement sur la grille (refait a chaque pose et toutes les 0,5 s)
local unavailableSaid = false
local open = false -- pose de blueprint active
local gridMode = false -- galerie dessinee a la place de la grille
local gtab = nil -- onglet ouvert en mode grille (nil = accueil)
local gpage = 1
local ptab = "all" -- onglet du panneau (repli)
local lastPerTab = {}
local lastWheel = nil
local lastBeat = nil
local drag = nil -- { slot, i, x, y }
local startDone = false
local leakHoverSaid, leakCmdSaid = false, false
local gridMissingSaid = false
local gridStale = true -- branchement sur la grille a refaire (ouverture de la pose, puis toutes les 0,5 s)
local nativeBroken = false -- le dessin avec les fonctions de la grille a echoue : dessin simplifie pour la partie
local shiftArmed = false -- Shift appuye pendant la pose, sans pose en file depuis : son relachement ne l'annule pas
local nativeBrokenSaid = false
local nativeFontOpen = false
local wheelMode = "select" -- option : "select" (molette = choisir) ou "rotate" (molette = tourner)
local configLoaded = false -- SetConfigData a fourni un reglage sous le nom actuel du widget
local OLD_WIDGET_NAME = "Galerie blueprints" -- ancien nom : son reglage est repris une fois
local optionAdded = false
local OPTION_ID = "galerie_blueprints_molette"
local stats = { reclass = 0, moves = 0, drawMs = 0, frames = 0 }

local function refresh()
	local reason
	h, reason = hook()
	if not h and not unavailableSaid then
		unavailableSaid = true
		eventEcho("indisponible : " .. tostring(reason) .. " — le jeu fonctionne comme sans la galerie.", "unavailable", tostring(reason))
	end
	return h
end

-- cases d'un onglet : slots[case] = index dans la liste ; « all » = ordre de la liste
local function tabLayout(tab)
	local slots, maxS = {}, 0
	if not h then
		return slots, 1
	end
	if tab == "all" then
		for i = 1, #h.list do
			slots[i] = i
		end
		return slots, mathMax(1, mathCeil(#h.list / CELLS))
	end
	local loose = {}
	for i, bp in ipairs(h.list) do
		if category(bp) == tab then
			local pcat, s = parseName(bp)
			if s and pcat == tab and not slots[s] then
				slots[s] = i
			else
				loose[#loose + 1] = i
			end
		end
	end
	local s = 1
	for _, i in ipairs(loose) do
		while slots[s] do
			s = s + 1
		end
		slots[s] = i
	end
	for k in pairs(slots) do
		maxS = mathMax(maxS, k)
	end
	return slots, mathMax(1, mathCeil(maxS / CELLS))
end

local function orderedIndices(tab)
	local slots = tabLayout(tab)
	local keys = {}
	for k in pairs(slots) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		out[#out + 1] = slots[k]
	end
	return out, slots
end

local function slotOf(tab, i)
	local slots = tabLayout(tab)
	for s, j in pairs(slots) do
		if j == i then
			return s
		end
	end
end

-- ecrit la case reelle de tous les blueprints de l'onglet : les lettres ne derivent plus ensuite
local function freeze(tab)
	if tab == "all" then
		return
	end
	local slots = tabLayout(tab)
	for s, i in pairs(slots) do
		setName(h.list[i], tab, s)
	end
end

local function firstFree(tab)
	local slots = tabLayout(tab)
	local s = 1
	while slots[s] do
		s = s + 1
	end
	return s
end

local function selectIndex(i)
	if not h or not h.list[i] then
		return false
	end
	if selectedIndex(h) == i then
		return false -- le jeu ecrirait la ligne « selected » meme sans changement
	end
	h.setSel(i)
	if h.sound then
		Spring.PlaySoundFile(h.sound, 0.75, nil, nil, nil, nil, nil, nil, "ui")
	end
	return true
end

local function nothingToChoose()
	mEcho("[Galerie] rien a choisir")
end

local function currentView()
	if gridMode then
		return gtab or "all"
	end
	return ptab
end

local function pageOfSelection(tab)
	local cur = h and selectedIndex(h)
	local s = cur and slotOf(tab, cur)
	return s and mathCeil(s / CELLS) or 1
end

-- clic droit : de la categorie automatique vers les 3 autres, puis retour a l'automatique
local function cycleCategory(i)
	local bp = h.list[i]
	local manual = parseName(bp)
	local auto = autoCategory(bp)
	local from = category(bp)
	local start = 1
	for k, c in ipairs(CATS) do
		if c == auto then
			start = k
		end
	end
	local order = {}
	for d = 1, #CATS - 1 do
		order[#order + 1] = CATS[(start - 1 + d) % #CATS + 1]
	end
	local nextCat
	if manual == nil or manual == auto then
		nextCat = order[1]
	else
		for k, c in ipairs(order) do
			if c == manual then
				nextCat = order[k + 1] -- nil apres la derniere : retour a l'automatique
			end
		end
	end
	freeze(from) -- les lettres de l'onglet quitte ne bougent pas
	if nextCat then
		setName(bp, nextCat, firstFree(nextCat))
	else
		setName(bp, nil)
	end
	stats.reclass = stats.reclass + 1
	local now = category(bp)
	mEcho(string.format("[Galerie] #%d classé en %s%s", i, catLabel(now), nextCat and "" or " (auto)"))
	return now
end

-- glisser : deplace ou echange deux cases d'un onglet
local function moveSlot(tab, fromSlot, toSlot)
	if tab == "all" or fromSlot == toSlot then
		return false
	end
	freeze(tab)
	local slots = tabLayout(tab)
	local a, b = slots[fromSlot], slots[toSlot]
	if not a then
		return false
	end
	setName(h.list[a], tab, toSlot)
	if b then
		setName(h.list[b], tab, fromSlot)
	end
	stats.moves = stats.moves + 1
	mEcho(string.format("[Galerie] rangement #%d case %d", a, toSlot))
	return true
end

-- mode grille : ouvrir un onglet (sans changer la selection : le fantome garde le blueprint courant)
local function openTab(tab)
	if tab == gtab then
		return
	end
	gtab = tab
	gpage = tab and pageOfSelection(tab) or 1
	local n = tab and #orderedIndices(tab) or #h.list
	mEcho(string.format("[Galerie] onglet %s (%d)", tab and catLabel(tab) or "accueil", n))
end

-- mode panneau (repli) : changer d'onglet choisit le dernier blueprint vu de l'onglet
local function setPanelTab(tab)
	if tab == ptab then
		return
	end
	ptab = tab
	local idx = orderedIndices(tab)
	mEcho(string.format("[Galerie] onglet %s (%d)", catLabel(tab), #idx))
	if #idx == 0 then
		return
	end
	local target = idx[1]
	local cur = selectedIndex(h)
	for _, i in ipairs(idx) do
		if i == lastPerTab[tab] then
			target = i
		end
	end
	for _, i in ipairs(idx) do
		if i == cur then
			target = cur
		end
	end
	selectIndex(target)
end

local function stepInView(dir)
	local view = currentView()
	local idx = orderedIndices(view)
	local cur = selectedIndex(h)
	if #idx == 0 or (#idx == 1 and idx[1] == cur) then
		nothingToChoose()
		return
	end
	local pos
	for k, i in ipairs(idx) do
		if i == cur then
			pos = k
		end
	end
	local k = pos and ((pos - 1 + dir) % #idx + 1) or (dir > 0 and 1 or #idx)
	selectIndex(idx[k])
	lastPerTab[view] = idx[k]
	if gridMode then
		gpage = pageOfSelection(view)
	end
end

local function stepTab(dir)
	if gridMode then
		-- accueil + 4 onglets de la grille, onglets vides sautes ; choisit le dernier blueprint vu de l'onglet
		local ring = { false, "eco", "combat", "util", "prod" }
		local pos = 1
		for k, t in ipairs(ring) do
			if t == (gtab or false) then
				pos = k
			end
		end
		for d = 1, #ring - 1 do
			local t = ring[(pos - 1 + dir * d) % #ring + 1]
			if t == false or #orderedIndices(t) > 0 then
				openTab(t or nil)
				if t then
					local idx = orderedIndices(t)
					local target = idx[1]
					for _, i in ipairs(idx) do
						if i == lastPerTab[t] or i == selectedIndex(h) then
							target = i
						end
					end
					selectIndex(target)
					gpage = pageOfSelection(t)
				end
				return
			end
		end
		nothingToChoose()
		return
	end
	local pos = 1
	for k, t in ipairs(PANEL_TABS) do
		if t == ptab then
			pos = k
		end
	end
	for d = 1, #PANEL_TABS - 1 do
		local t = PANEL_TABS[(pos - 1 + dir * d) % #PANEL_TABS + 1]
		if t == "all" or #orderedIndices(t) > 0 then
			setPanelTab(t)
			return
		end
	end
	nothingToChoose()
end

--------------------------------------------------------------------------------
-- Touches de la grille (mode grille uniquement)
--------------------------------------------------------------------------------

local function modifierBlocks()
	local alt, ctrl, meta = spGetModKeyState()
	return alt or ctrl or meta -- Alt+W/X : espacement du blueprint (ou file d'usine) : laisse au jeu
end

-- une seule fonction pour « gridmenu_category N » et « gridmenu_key 1 N » : l'ordre des actions est sans effet
local function gridKey(row, col)
	if not gtab then
		if row == 1 and CATS[col] then
			openTab(CATS[col])
		else
			nothingToChoose()
		end
		return
	end
	local slots = tabLayout(gtab)
	local i = slots[(gpage - 1) * CELLS + (row - 1) * 4 + col]
	if i then
		selectIndex(i)
		lastPerTab[gtab] = i
	else
		nothingToChoose()
	end
end

local function onGridKey(_, _, words, _, isRepeat)
	if not gridMode or modifierBlocks() then
		return false
	end
	if isRepeat then
		return true -- touche tenue : consommee, sans effet (sinon elle retomberait sur la grille ou attack/repair...)
	end
	local row, col = tonumber(words and words[1]), tonumber(words and words[2])
	if row and col then
		gridKey(row, col)
	end
	return true
end

local function onGridCategory(_, _, words, _, isRepeat)
	if not gridMode or modifierBlocks() then
		return false
	end
	if isRepeat then
		return true
	end
	local col = tonumber(words and words[1])
	if col then
		gridKey(1, col)
	end
	return true
end

local function onNextPage(_, _, _, _, isRepeat)
	if not gridMode or modifierBlocks() then
		return false
	end
	if isRepeat then
		return true
	end
	local view = gtab or "all"
	local _, pages = tabLayout(view)
	if pages < 2 then
		nothingToChoose()
		return true
	end
	gpage = gpage % pages + 1
	mEcho(string.format("[Galerie] onglet %s page %d", gtab and catLabel(gtab) or "accueil", gpage))
	return true
end

--------------------------------------------------------------------------------
-- Grille rendue aveugle a la souris pendant la pose (sure par construction)
--------------------------------------------------------------------------------

local wrappedBg, wrappedOrig, wrapper

local function galleryAlive()
	return gridMode and lastBeat ~= nil and spDiffTimers(spGetTimer(), lastBeat) < HEARTBEAT_S
end

local function installWrapper(bg)
	if wrappedBg == bg and bg.contains == wrapper then
		return
	end
	local orig = bg.contains
	local w = function(self, x, y)
		if galleryAlive() then
			return false
		end
		return orig(self, x, y)
	end
	bg.contains = w
	wrappedBg, wrappedOrig, wrapper = bg, orig, w
end

local function restoreWrapper()
	if wrappedBg and wrapper and wrappedBg.contains == wrapper then
		wrappedBg.contains = wrappedOrig
	end
	wrappedBg, wrappedOrig, wrapper = nil, nil, nil
end

--------------------------------------------------------------------------------
-- Verrou de partie et journal des noms voulus (editeur hors partie)
--------------------------------------------------------------------------------

local lastLock = nil

local function writeLock()
	if not MEASURE then
		return -- version publique : rien d'ecrit sur disque
	end
	pcall(function()
		local f = io.open(LOCK_FILE, "w")
		if f then
			f:write("partie en cours ; image " .. tostring(Spring.GetGameFrame()) .. "\n")
			f:close()
		end
	end)
	lastLock = spGetTimer()
end

-- signature d'un blueprint : types, positions arrondies a 1 elmo, orientation de chaque unite, triees
local function signature(bp)
	local parts = {}
	for _, u in ipairs(bp.units or {}) do
		-- en memoire : originalName ; blueprint masque (forme serialisee du fichier) : unitName
		local name = u.originalName or u.unitName or (u.unitDefID and UnitDefs[u.unitDefID] and UnitDefs[u.unitDefID].name) or "?"
		parts[#parts + 1] = string.format(
			"%s:%d:%d:%d",
			name,
			mathFloor(u.position[1] + 0.5),
			mathFloor(u.position[3] + 0.5),
			u.facing or 0
		)
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

local function readJson(path)
	local ok, content = pcall(VFS.LoadFile, path)
	if not ok or not content or not Json then
		return nil
	end
	local ok2, data = pcall(Json.decode, content)
	return ok2 and data or nil
end

-- fusion a trois : on ne remet le nom voulu que si le nom actuel est encore celui de depart
local function applyJournal()
	local j = readJson(JOURNAL_FILE)
	if type(j) ~= "table" or j.etat ~= "en attente" or type(j.entrees) ~= "table" then
		return
	end
	-- blueprints en memoire ET blueprints masques (faction absente) : le jeu reecrit les noms des deux
	local bySig = {}
	local function add(bp)
		local s = signature(bp)
		bySig[s] = bySig[s] or {}
		table.insert(bySig[s], bp)
	end
	for _, bp in ipairs(h.list) do
		add(bp)
	end
	for _, bp in ipairs(h.hiddenList or {}) do
		add(bp)
	end
	local used = {}
	local applied, kept, done, pending = 0, 0, 0, {}
	local function nameOf(bp)
		return type(bp.name) == "string" and bp.name or ""
	end
	-- doublons (meme signature) : chaque entree prend son propre blueprint, jamais deux fois le meme ; passes
	-- successives (deja conforme, puis encore au nom de depart, puis range en jeu depuis), comme l'editeur
	local entries, picked = {}, {}
	for _, e in ipairs(j.entrees) do
		if type(e) == "table" and type(e.voulu) == "string" then
			entries[#entries + 1] = e
		end
	end
	local function pass(test, how)
		for k, e in ipairs(entries) do
			if not picked[k] then
				for _, bp in ipairs(bySig[e.signature] or {}) do
					if not used[bp] and test(bp, e) then
						used[bp], picked[k] = true, { bp = bp, how = how }
						break
					end
				end
			end
		end
	end
	pass(function(bp, e) return nameOf(bp) == e.voulu end, "conforme")
	pass(function(bp, e) return nameOf(bp) == (e.depart or "") end, "remis")
	pass(function() return true end, "garde")
	for k, e in ipairs(entries) do
		local p = picked[k]
		if not p then
			pending[#pending + 1] = e -- introuvable dans cette partie : reste en attente, jamais perdu
		elseif p.how == "remis" then
			p.bp.name = e.voulu
			catCache[p.bp] = nil
			applied = applied + 1
		elseif p.how == "garde" then
			kept = kept + 1 -- range en jeu depuis : le rangement en jeu prime
		else
			done = done + 1
		end
	end
	local suffix = (kept > 0 and (" (gardées en jeu " .. kept .. ")") or "")
		.. (#pending > 0 and (" (en attente " .. #pending .. ")") or "")
	if applied > 0 then
		mEcho(string.format("[Editeur] disposition réappliquée %d%s", applied, suffix))
	else
		mEcho("[Editeur] disposition conforme" .. suffix)
	end
	j.entrees = pending
	j.etat = #pending > 0 and "en attente" or "appliqué"
	pcall(function()
		local encoded = Json.encode(j)
		local f = encoded and io.open(JOURNAL_FILE, "w")
		if f then
			f:write(encoded)
			f:close()
		end
	end)
end

local function startOfGame()
	startDone = true
	local d = readJson(BLUEPRINT_FILE)
	local n = (type(d) == "table" and type(d.savedBlueprints) == "table") and #d.savedBlueprints or -1
	mEcho(string.format("[Galerie] chargement fichier=%d memoire=%d masques=%d", n, #h.list, h.hidden))
	if MEASURE then
		applyJournal() -- journal de l'editeur hors partie : seulement chez le joueur qui l'utilise
	end
end

--------------------------------------------------------------------------------
-- Mise en page
--------------------------------------------------------------------------------

local vsx, vsy = Spring.GetViewGeometry()
local L = {} -- mise en page courante (grille ou panneau)
local font
local displayList
local listKey
local hover = nil -- { kind = "card"|"tab", i, tab, slot }

local function rectOf(r)
	return { x0 = r.x, y0 = r.y, x1 = r.xEnd, y1 = r.yEnd }
end

local function layoutGrid()
	local view = gtab or "all"
	local slots, pages = tabLayout(view)
	if gpage > pages then
		gpage = pages
	end
	local b = grid.bg
	L = { mode = "grid", x0 = b.x, y0 = b.y, x1 = b.xEnd, y1 = b.yEnd, pages = pages, page = gpage, view = view }
	L.tabs = {}
	for k, c in ipairs(CATS) do
		local r = rectOf(grid.cat[c])
		r.tab = c
		local opts = grid.cat[c].opts or {}
		r.key = opts.keyText or ""
		L.tabs[k] = r
	end
	L.cards = {}
	for n = 1, CELLS do
		local cr = grid.cellRects[n]
		if cr and cr.xEnd and cr.xEnd > cr.x then
			local r = rectOf(cr)
			local row, col = mathFloor((n - 1) / 4) + 1, (n - 1) % 4 + 1
			r.slot = (gpage - 1) * CELLS + n
			r.i = slots[r.slot]
			r.key = sanitizeKey(grid, grid.keyLayout[row] and grid.keyLayout[row][col])
			L.cards[#L.cards + 1] = r
		end
	end
	L.card = L.cards[1] and (L.cards[1].x1 - L.cards[1].x0) or 40
	L.pad = mathMax(2, mathFloor(L.card * 0.06))
	L.tabH = L.tabs[1] and (L.tabs[1].y1 - L.tabs[1].y0) or 20
	-- aspect de la grille : dans une categorie, la barre du bas devient « ⟵ Back SHIFT » + la categorie ouverte,
	-- comme sur la grille standard ; bouton de page si besoin
	L.buttons = {}
	local N = grid.native
	if N then
		L.native = true
		if gtab then
			L.tabs = {}
			L.buttons[#L.buttons + 1] = { kind = "back", r = rectOf(N.backRect) }
			L.buttons[#L.buttons + 1] = { kind = "cur", r = rectOf(N.curRect) }
		end
		if pages > 1 and gtab then -- a l'accueil, le bouton recouvrirait les onglets Utility et Build
			L.buttons[#L.buttons + 1] = { kind = "next", r = rectOf(N.nextRect) }
		end
	end
end

local function layoutPanel()
	local scale = (WG.FlowUI and WG.FlowUI.scale) or 1
	local card = mathFloor(vsy * 0.072 * scale)
	local pad = mathMax(2, mathFloor(card * 0.08))
	local cols = 6
	local tabH = mathFloor(vsy * 0.026 * scale)
	local hintH = mathFloor(vsy * 0.018 * scale)
	local idx = orderedIndices(ptab)
	local rows = mathMax(1, mathMin(2, mathCeil(#idx / cols)))
	local width = cols * (card + pad) + pad
	local height = pad + tabH + pad + rows * (card + pad) + hintH

	local bottom = mathFloor(vsy * 0.30)
	if WG.buildmenu and WG.buildmenu.getSize then
		local ok, a, b = pcall(WG.buildmenu.getSize)
		if ok and type(a) == "number" and type(b) == "number" then
			bottom = mathMax(a, b) + pad
		end
	end
	bottom = mathMin(bottom, vsy - height)

	L = {
		mode = "panel", x0 = 0, y0 = bottom, x1 = width, y1 = bottom + height,
		card = card, pad = pad, cols = cols, rows = rows, tabH = tabH, hintH = hintH,
	}
	L.tabs = {}
	local tw = (width - pad) / #PANEL_TABS
	for k, t in ipairs(PANEL_TABS) do
		local x = pad + (k - 1) * tw
		L.tabs[k] = { tab = t, x0 = x, x1 = x + tw - pad, y0 = L.y1 - pad - tabH, y1 = L.y1 - pad }
	end
	local per = cols * rows
	local cur = h and selectedIndex(h)
	local pos = 1
	for k, i in ipairs(idx) do
		if i == cur then
			pos = k
		end
	end
	local first = mathFloor((pos - 1) / per) * per + 1
	L.cards = {}
	L.pages = mathMax(1, mathCeil(#idx / per))
	L.page = mathFloor((first - 1) / per) + 1
	for s = 0, per - 1 do
		local i = idx[first + s]
		if not i then
			break
		end
		local col, row = s % cols, mathFloor(s / cols)
		local x = pad + col * (card + pad)
		local yTop = L.tabs[1].y0 - pad - row * (card + pad)
		L.cards[#L.cards + 1] = { i = i, x0 = x, x1 = x + card, y0 = yTop - card, y1 = yTop }
	end
end

local function inside(r, x, y)
	return r and r.x0 and x >= r.x0 and x <= r.x1 and y >= r.y0 and y <= r.y1
end

-- n'appelle jamais backgroundRect:contains (enveloppe) : rectangles propres
local function hitTest(x, y)
	if not open or not L.x0 or not inside(L, x, y) then
		return nil
	end
	for _, c in ipairs(L.cards or {}) do
		if inside(c, x, y) then
			return { kind = "card", i = c.i, slot = c.slot }
		end
	end
	for _, t in ipairs(L.tabs or {}) do
		if inside(t, x, y) then
			return { kind = "tab", tab = t.tab }
		end
	end
	for _, b in ipairs(L.buttons or {}) do
		if inside(b.r, x, y) then
			return { kind = b.kind }
		end
	end
	return { kind = "panel" }
end

--------------------------------------------------------------------------------
-- Dessin
--------------------------------------------------------------------------------

local function rect(x0, y0, x1, y1, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x0, y0, x1, y1)
end

local function buildingSize(unitDefID, facing)
	if WG.api_blueprint and WG.api_blueprint.getBuildingDimensions then
		return WG.api_blueprint.getBuildingDimensions(unitDefID, facing)
	end
	local ud = UnitDefs[unitDefID]
	local sq = Game.squareSize or 8
	if facing % 2 == 1 then
		return sq * ud.zsize, sq * ud.xsize
	end
	return sq * ud.xsize, sq * ud.zsize
end

local function drawThumbnail(bp, c)
	local units = bp.units
	if WG.api_blueprint and WG.api_blueprint.rotateBlueprint and (bp.facing or 0) ~= 0 then
		local ok, rotated = pcall(WG.api_blueprint.rotateBlueprint, bp, bp.facing)
		if ok and rotated and rotated.units then
			units = rotated.units
		end
	end
	local boxes = {}
	local xMin, xMax, zMin, zMax
	for _, u in ipairs(units) do
		if u.unitDefID and UnitDefs[u.unitDefID] then
			local w, d = buildingSize(u.unitDefID, u.facing or 0)
			local x, z = u.position[1], u.position[3]
			boxes[#boxes + 1] = { u.unitDefID, x - w / 2, z - d / 2, x + w / 2, z + d / 2 }
			xMin = xMin and mathMin(xMin, x - w / 2) or x - w / 2
			xMax = xMax and mathMax(xMax, x + w / 2) or x + w / 2
			zMin = zMin and mathMin(zMin, z - d / 2) or z - d / 2
			zMax = zMax and mathMax(zMax, z + d / 2) or z + d / 2
		end
	end
	if not xMin then
		return
	end
	local inner = (c.x1 - c.x0) * 0.80
	local s = inner / mathMax(xMax - xMin, zMax - zMin, 1)
	local cx = (c.x0 + c.x1) / 2 - (xMin + xMax) / 2 * s
	local cy = (c.y0 + c.y1) / 2 + (zMin + zMax) / 2 * s -- z du monde vers le bas de l'ecran
	gl.Color(1, 1, 1, 1)
	for _, b in ipairs(boxes) do
		gl.Texture("#" .. b[1])
		gl.TexRect(cx + b[2] * s, cy - b[5] * s, cx + b[4] * s, cy - b[3] * s)
	end
	gl.Texture(false)
end

local function drawGeometry()
	local sel = h and selectedIndex(h)
	if L.mode == "grid" then
		-- fond opaque a la place exacte de la grille (la grille reste dessinee dessous, invisible)
		rect(L.x0, L.y0, L.x1, L.y1, 0.06, 0.06, 0.08, 1)
		if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element then
			pcall(WG.FlowUI.Draw.Element, L.x0, L.y0, L.x1, L.y1, 1, 1, 1, 1)
		end
	else
		rect(L.x0, L.y0, L.x1, L.y1, 0.05, 0.05, 0.07, 0.82)
	end
	local activeTab = L.mode == "grid" and gtab or ptab
	for _, t in ipairs(L.tabs) do
		local active = t.tab == activeTab
		local hov = hover and hover.kind == "tab" and hover.tab == t.tab
		local col = COLOR[t.tab] or { 0.8, 0.8, 0.8 }
		rect(t.x0, t.y0, t.x1, t.y1, col[1] * 0.35, col[2] * 0.35, col[3] * 0.35, active and 0.95 or (hov and 0.7 or 0.45))
		if active then
			rect(t.x0, t.y0, t.x1, t.y0 + mathMax(2, L.pad * 0.5), col[1], col[2], col[3], 1)
		end
	end
	for _, c in ipairs(L.cards) do
		local hov = hover and hover.kind == "card" and (hover.slot or hover.i) == (c.slot or c.i)
		local dragged = drag and drag.slot and drag.slot == c.slot
		rect(c.x0, c.y0, c.x1, c.y1, 0.12, 0.12, 0.15, (hov or dragged) and 1 or 0.9)
		if c.i then
			local bp = h.list[c.i]
			local col = COLOR[category(bp)]
			if c.i == sel then
				rect(c.x0, c.y0, c.x1, c.y0 + 2, 1, 1, 1, 1)
				rect(c.x0, c.y1 - 2, c.x1, c.y1, 1, 1, 1, 1)
				rect(c.x0, c.y0, c.x0 + 2, c.y1, 1, 1, 1, 1)
				rect(c.x1 - 2, c.y0, c.x1, c.y1, 1, 1, 1, 1)
			end
			rect(c.x0, c.y1 - mathMax(2, L.pad * 0.5), c.x1, c.y1, col[1], col[2], col[3], 0.9)
			drawThumbnail(bp, c)
		end
		if drag and hov and not dragged then
			rect(c.x0, c.y0, c.x1, c.y1, 1, 1, 1, 0.15) -- case de depot
		end
	end
	gl.Color(1, 1, 1, 1)
end

local function drawTexts()
	local f = font
	local function text(s, x, y, sz, opt)
		if f then
			f:Print(s, x, y, sz, opt)
		else
			gl.Text(s, x, y, sz, opt)
		end
	end
	if f then
		f:Begin()
		f:SetTextColor(1, 1, 1, 1)
		f:SetOutlineColor(0, 0, 0, 1)
	end
	local size = L.tabH * 0.5
	local sel = h and selectedIndex(h)
	if L.mode == "grid" then
		for _, t in ipairs(L.tabs) do
			text(catLabel(t.tab), t.x0 + L.pad * 2, (t.y0 + t.y1) / 2 - size * 0.35, size, "o")
			if not gtab and t.key ~= "" then
				text("\255\215\255\215" .. t.key, t.x1 - L.pad * 2, (t.y0 + t.y1) / 2 - size * 0.35, size, "ro")
			end
		end
		for _, c in ipairs(L.cards) do
			local ks = L.card * 0.2
			if gtab and c.key ~= "" then
				text("\255\215\255\215" .. c.key, c.x1 - L.pad, c.y1 - ks * 1.1, ks, "ro")
			end
			if c.i then
				text((c.i == sel and "\255\255\255\120" or "\255\200\200\200") .. "#" .. c.i, c.x0 + L.pad, c.y0 + L.pad, ks * 0.8, "o")
			end
		end
		if L.pages > 1 then
			text(string.format("\255\170\170\170%d/%d", L.page, L.pages), L.x1 - L.pad * 2, L.y1 - size * 1.3, size * 0.8, "ro")
		end
	else
		for _, t in ipairs(L.tabs) do
			text(catLabel(t.tab), (t.x0 + t.x1) / 2, (t.y0 + t.y1) / 2 - size * 0.35, size, "co")
		end
		for _, c in ipairs(L.cards) do
			local bp = h.list[c.i]
			local manual = parseName(bp)
			local label = "#" .. c.i .. (manual and "" or " ·auto")
			text((c.i == sel and "\255\255\255\120" or "\255\220\220\220") .. label, c.x0 + L.pad * 0.6, c.y0 + L.pad * 0.6, L.card * 0.16, "o")
			text("\255\180\180\180" .. #bp.units, c.x1 - L.pad * 0.6, c.y0 + L.pad * 0.6, L.card * 0.16, "ro")
		end
		if #L.cards == 0 then
			text("\255\180\180\180" .. tr("empty"), (L.x0 + L.x1) / 2, L.y0 + L.hintH + L.card * 0.5, size, "co")
		end
		local extra = L.pages > 1 and string.format("%s %d/%d  ·  ", tr("page"):lower(), L.page, L.pages) or ""
		text("\255\170\170\170" .. extra .. tr(wheelMode == "rotate" and "hintRotate" or "hintSelect"), L.x0 + L.pad, L.y0 + L.hintH * 0.3, L.hintH * 0.62, "o")
	end
	if f then
		f:End()
	end
end

--------------------------------------------------------------------------------
-- Dessin avec les fonctions de la grille (aspect identique a la grille standard)
--------------------------------------------------------------------------------

local function gridRect(r, opts)
	return {
		x = r.x0, y = r.y0, xEnd = r.x1, yEnd = r.y1, opts = opts or {},
		getWidth = function(self) return self.xEnd - self.x end,
		getHeight = function(self) return self.yEnd - self.y end,
		contains = function() return false end,
	}
end

local function drawNative()
	local N = grid.native
	local f = N.font
	local sel = h and selectedIndex(h)
	f:Begin(true)
	nativeFontOpen = true
	f:SetTextColor(1, 1, 1, 1)
	f:SetOutlineColor(0, 0, 0, 1)
	-- base opaque sous le fond de la grille : le fond de la grille est translucide (il laisse voir la carte floutee)
	-- et la grille reste dessinee dessous ; sans cette base, ses batiments transparaissent (retour du joueur)
	local b = grid.bg
	local height = b.yEnd - b.y
	local cs = (WG.FlowUI and WG.FlowUI.elementCorner) or N.cornerSize
	N.RectRound(b.x, b.y, b.xEnd, b.yEnd, cs,
		(b.x > 0) and 1 or 0, 1, ((b.y - height > 0 or b.x <= 0) and 1 or 0), 0, -- memes coins que drawBuildMenuBg
		{ 0.075, 0.075, 0.085, 1 }, { 0.095, 0.095, 0.105, 1 })
	N.bg()
	local keyFont = N.priceFontSize * 1.1
	local textX = N.cellPadding + N.cellInnerSize * 0.048
	for _, c in ipairs(L.cards) do
		N.cell(gridRect(c)) -- case vide de la grille (fond)
		if c.i then
			local bp = h.list[c.i]
			local pad = N.cellPadding + N.iconPadding
			local r = { x0 = c.x0 + pad, y0 = c.y0 + pad, x1 = c.x1 - pad, y1 = c.y1 - pad }
			local hov = hover and hover.kind == "card" and hover.slot == c.slot
			-- fond sombre et opaque : seul le plan du blueprint se voit (l'image du batiment principal en fond,
			-- meme assombrie, se lisait comme des objets en transparence : retour du joueur)
			N.RectRound(r.x0, r.y0, r.x1, r.y1, N.cornerSize, 1, 1, 1, 1, { 0.11, 0.115, 0.13, 1 }, { 0.16, 0.165, 0.18, 1 })
			drawThumbnail(bp, r)
			if c.i == sel then -- couleur « choisi » de la grille
				N.RectRound(r.x0, r.y0, r.x1, r.y1, N.cornerSize, 1, 1, 1, 1, { 1, 0.85, 0.2, 0.25 }, { 1, 0.85, 0.2, 0.25 })
			elseif hov or (drag and drag.slot == c.slot) then
				N.RectRound(r.x0, r.y0, r.x1, r.y1, N.cornerSize, 1, 1, 1, 1, { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.14 })
			end
			gl.Color(1, 1, 1, 1)
			if gtab and c.key ~= "" then
				f:Print("\255\215\255\215" .. c.key, c.x1 - textX, c.y1 - N.cellPadding - keyFont, keyFont, "ro")
			end
			f:Print("\255\245\245\245" .. #bp.units, c.x1 - textX, c.y0 + N.cellPadding + N.priceFontSize * 0.35, N.priceFontSize, "ro")
		elseif drag and hover and hover.kind == "card" and hover.slot == c.slot then
			local pad = N.cellPadding + N.iconPadding
			N.RectRound(c.x0 + pad, c.y0 + pad, c.x1 - pad, c.y1 - pad, N.cornerSize, 1, 1, 1, 1, { 1, 1, 1, 0.08 }, { 1, 1, 1, 0.16 })
		end
	end
	local function label(rect, name, nameHeight)
		local hgt = rect.yEnd - rect.y
		f:Print(name, rect.x + N.bgpadding * 7, (rect.y + hgt / 2) - (nameHeight or 1) * N.catFont * 0.34, N.catFont, "o")
	end
	if gtab then
		N.drawBack() -- « ⟵ Back » + SHIFT, dessine par la grille elle-meme
		local opts = grid.cat[gtab].opts or {}
		local cr = N.curRect
		label(cr, opts.name or catLabel(gtab), opts.nameHeight)
		N.button(gridRect(rectOf(cr), { icon = opts.icon, hovered = hover and hover.kind == "cur" }))
	else
		for _, c in ipairs(CATS) do
			local r = grid.cat[c]
			local opts = r.opts or {}
			label(r, opts.name or catLabel(c), opts.nameHeight)
			N.hotkey(gridRect(rectOf(r), { keyText = opts.keyText, keyTextHeight = opts.keyTextHeight }))
			N.button(gridRect(rectOf(r), { icon = opts.icon, hovered = hover and hover.kind == "tab" and hover.tab == c }))
		end
	end
	if L.pages > 1 and not gtab then
		-- accueil de plus de 12 blueprints : la vraie grille n'a pas ce cas (son bouton de page recouvrirait les
		-- onglets) ; simple indication, la page change avec la touche de page ou la molette
		local txt = "\255\170\170\170" .. tr("page") .. " " .. L.page .. "/" .. L.pages
		f:Print(txt, L.x1 - N.bgpadding * 4, L.y1 - N.pageFont * 1.2, N.pageFont * 0.8, "ro")
	elseif L.pages > 1 then -- bouton de page de la grille, avec nos numeros
		local nr = N.nextRect
		local txt = "\255\245\245\245" .. tr("page") .. " " .. L.page .. "/" .. L.pages .. "  🠚"
		local fh = f:GetTextHeight(txt) * N.pageFont
		f:Print(txt, nr.x + N.bgpadding * 3, (nr.y + (nr.yEnd - nr.y) / 2) - fh * 0.34, N.pageFont, "o")
		local key = sanitizeKey(grid, N.nextKey)
		N.hotkey(gridRect(rectOf(nr), { keyText = key, keyTextHeight = f:GetTextHeight(key) }))
		N.button(gridRect(rectOf(nr), { hovered = hover and hover.kind == "next" }))
	end
	f:End()
	nativeFontOpen = false
	gl.Color(1, 1, 1, 1)
end

local function geometryKey()
	local parts = { L.mode, tostring(gtab), gpage, ptab, tostring(h and selectedIndex(h)), vsx, vsy, L.x0, L.y0, L.x1, L.y1, #h.list }
	if hover then
		parts[#parts + 1] = hover.kind .. tostring(hover.slot or hover.i or hover.tab)
	end
	if drag then
		parts[#parts + 1] = "drag" .. tostring(drag.slot)
	end
	for _, c in ipairs(L.cards) do
		local bp = c.i and h.list[c.i]
		parts[#parts + 1] = tostring(c.slot) .. ":" .. (bp and (tostring(bp) .. ":" .. tostring(bp.facing) .. ":" .. tostring(bp.name) .. ":" .. #bp.units) or "-")
	end
	return table.concat(parts, "|")
end

--------------------------------------------------------------------------------
-- Callins
--------------------------------------------------------------------------------

-- option dans les parametres du jeu (onglet des widgets, sous « Blueprint Gallery GRID »), traduite, gardee d'une partie a l'autre
local function addOption()
	if optionAdded or not (WG.options and WG.options.addOption) then
		return
	end
	optionAdded = true
	pcall(WG.options.addOption, {
		id = OPTION_ID,
		widgetname = WIDGET_NAME,
		name = tr("optName"),
		type = "select",
		options = { tr("optSelect"), tr("optRotate") },
		value = wheelMode == "rotate" and 2 or 1,
		description = tr("optDesc"),
		onchange = function(_, value)
			wheelMode = (value == 2) and "rotate" or "select"
		end,
	})
end

-- le joueur change la langue du jeu : textes et option suivent tout de suite
function widget:LanguageChanged()
	detectLanguage()
	if optionAdded and WG.options and WG.options.removeOption then
		pcall(WG.options.removeOption, OPTION_ID)
		optionAdded = false
	end
	addOption()
	listKey = nil
end

function widget:GetConfigData()
	return { wheelMode = wheelMode }
end

function widget:SetConfigData(data)
	if type(data) == "table" and (data.wheelMode == "select" or data.wheelMode == "rotate") then
		wheelMode = data.wheelMode
		configLoaded = true
	end
end

function widget:Initialize()
	if WG.fonts and WG.fonts.getFont then
		font = WG.fonts.getFont(2)
	end
	detectLanguage()
	if not configLoaded then
		-- renommage « Galerie blueprints » -> « Blueprint Gallery GRID » : le jeu range les reglages par nom de
		-- widget ; on reprend une fois le reglage de molette enregistre sous l'ancien nom
		local cd = widgetHandler and widgetHandler.configData
		local old = type(cd) == "table" and cd[OLD_WIDGET_NAME]
		if type(old) == "table" and (old.wheelMode == "select" or old.wheelMode == "rotate") then
			wheelMode = old.wheelMode
		end
	end
	local ok, exists = pcall(VFS.FileExists, MEASURE_FLAG)
	MEASURE = ok and exists and true or false
	addOption()
	writeLock() -- dans tous les modes, meme si la galerie est indisponible
	local ah = widgetHandler and widgetHandler.actionHandler
	if ah and ah.AddAction then
		ah:AddAction(widget, "gridmenu_key", onGridKey, nil, "pR")
		ah:AddAction(widget, "gridmenu_category", onGridCategory, nil, "pR")
		ah:AddAction(widget, "gridmenu_next_page", onNextPage, nil, "pR")
	end
end

function widget:ViewResize(x, y)
	vsx, vsy = x, y
	-- la grille recalcule ses tailles et reprend une police neuve : branchement a refaire, dessin natif a reessayer
	gridStale = true
	nativeBroken = false
	if WG.fonts and WG.fonts.getFont then
		font = WG.fonts.getFont(2)
	end
end

local function computeGridMode()
	if not (open and h) then
		return false
	end
	if gridStale then
		grid = gridHook()
		gridStale = false
		if grid and nativeBroken then
			grid.native = nil
		end
	end
	if not grid then
		if not gridMissingSaid and WG.buildmenu and WG.buildmenu.getIsShowing then
			gridMissingSaid = true
			eventEcho("grille introuvable : repli sur le panneau (mise à jour du jeu ?)", "gridMissing")
		end
		return false
	end
	if Spring.IsGUIHidden and Spring.IsGUIHidden() then
		return false
	end
	local ok, showing = pcall(grid.isShowing)
	if not ok or not showing then
		return false
	end
	local b = grid.bg
	return b.xEnd > b.x and b.yEnd > b.y
end

local function setOpen(v)
	if v == open then
		return
	end
	open = v
	drag = nil
	if v then
		if not refresh() then
			open = false
			return
		end
		gtab, gpage = nil, 1 -- chaque pose commence a l'accueil, comme la grille
		leakHoverSaid, leakCmdSaid, shiftArmed = false, false, false
		gridStale = true
		nativeBroken = false -- nouvel essai du dessin de la grille a chaque pose
		local cur = selectedIndex(h)
		ptab = (cur and h.list[cur]) and category(h.list[cur]) or "all"
	end
end

local updateTimer = 0
local prevCmd = nil
function widget:Update(dt)
	if not optionAdded then
		addOption() -- le menu des options peut se charger apres la galerie
	end
	if not lastLock or spDiffTimers(spGetTimer(), lastLock) > LOCK_EVERY_S then
		writeLock()
	end
	if not startDone and refresh() then
		startOfGame()
	end
	local _, cmdID = spGetActiveCommand()
	-- fuite : pendant la pose en mode grille, une autre commande a remplace la pose (construction si < 0).
	-- Echap et clic droit annulent la pose vers « aucune commande » (nil ou 0) : pas une fuite.
	if prevCmd == CMD_BLUEPRINT_PLACE and cmdID and cmdID ~= 0 and cmdID ~= CMD_BLUEPRINT_PLACE and gridMode and not leakCmdSaid then
		leakCmdSaid = true
		mEcho("[Galerie] fuite grille commande " .. tostring(cmdID))
	end
	prevCmd = cmdID
	setOpen(cmdID == CMD_BLUEPRINT_PLACE)
	if not open then
		gridMode = false
		return
	end
	updateTimer = updateTimer + dt
	if updateTimer > 0.5 then
		updateTimer = 0
		gridStale = true
		if not refresh() then
			open, gridMode = false, false
			return
		end
	end
	for k in pairs(catCache) do
		catCache[k] = nil
	end
	-- fuite : la grille a vu la souris pendant la pose (ne devrait jamais arriver avec l'enveloppe)
	if gridMode and WG.buildmenu and WG.buildmenu.hoverID ~= nil and not leakHoverSaid then
		leakHoverSaid = true
		mEcho("[Galerie] fuite grille survol")
	end
	gridMode = computeGridMode()
	if gridMode then
		installWrapper(grid.bg)
		lastBeat = spGetTimer()
		layoutGrid()
	else
		layoutPanel()
	end
	local mx, my = spGetMouseState()
	hover = hitTest(mx, my)
	if hover and hover.kind == "panel" then
		hover = nil
	end
	if hover and hover.kind == "card" and hover.i and WG.tooltip and WG.tooltip.ShowTooltip then
		local bp = h.list[hover.i]
		WG.tooltip.ShowTooltip(
			"galerie_blueprints",
			tr("tooltip", hover.i, #bp.units, catLabel(category(bp)))
		)
	end
	if inside(L, mx, my) then
		Spring.SetMouseCursor("cursornormal")
	end
end

function widget:DrawScreen()
	if not open or not h or not L.tabs then
		return
	end
	local t0 = spGetTimerMicros and spGetTimerMicros()
	local drawn = false
	if L.mode == "grid" and L.native and grid and grid.native then
		local N = grid.native
		local ok, err = pcall(drawNative)
		if ok then
			drawn = true
		else
			nativeBroken = true
			grid.native = nil
			if nativeFontOpen and N.font then
				pcall(N.font.End, N.font) -- police partagee (cache WG.fonts) : jamais laissee ouverte
			end
			nativeFontOpen = false
			if GL and gl.Blending then
				pcall(gl.Blending, GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
			end
			pcall(gl.Texture, false)
			pcall(gl.Color, 1, 1, 1, 1)
			if not nativeBrokenSaid then
				nativeBrokenSaid = true
				eventEcho("dessin de la grille indisponible, dessin simplifié : " .. tostring(err), "nativeBroken", tostring(err))
			end
		end
	end
	if not drawn then
		local key = geometryKey()
		if key ~= listKey or not displayList then
			if displayList then
				gl.DeleteList(displayList)
			end
			displayList = gl.CreateList(drawGeometry)
			listKey = key
		end
		gl.CallList(displayList)
		drawTexts()
	end
	if t0 then
		stats.drawMs = stats.drawMs + spDiffTimers(spGetTimerMicros(), t0, true, true) -- en ms, depuis des microsecondes
		stats.frames = stats.frames + 1
	end
end

function widget:IsAbove(x, y)
	return hitTest(x, y) ~= nil
end

local SHIFT_KEYS = { [(KEYSYMS and KEYSYMS.LSHIFT) or 304] = true, [(KEYSYMS and KEYSYMS.RSHIFT) or 303] = true }

function widget:KeyPress(key, mods, isRepeat)
	if SHIFT_KEYS[key] then
		if gridMode and not isRepeat then
			shiftArmed = true
		end
		return false -- Shift reste disponible pour le jeu (pose en file)
	end
	if key == KEY_ESCAPE and gridMode and gtab then
		openTab(nil) -- 1er Echap : retour a l'accueil ; le 2e annule la pose (jeu)
		return true
	end
	return false
end

-- Shift, comme sur la grille standard (« ⟵ Back  SHIFT ») : son relachement ramene a l'accueil. La galerie garde
-- ce relachement (sinon la grille ferme sa categorie ET annule la commande active, donc la pose), sauf apres une
-- pose en file (clic sur la carte avec Shift tenu) : la, il reste au jeu, comme aujourd'hui. Shift tenu puis une
-- lettre, Echap ou un clic dans la galerie ne comptent pas comme pose en file.
function widget:KeyRelease(key)
	if SHIFT_KEYS[key] and shiftArmed then
		shiftArmed = false
		if gridMode then
			if gtab then
				openTab(nil)
			end
			return true
		end
	end
	return false
end

function widget:MousePress(x, y, button)
	local hit = hitTest(x, y)
	if not hit then
		shiftArmed = false -- clic sur la carte avec Shift tenu = pose en file : le relachement reste au jeu
	end
	if button ~= 1 and button ~= 3 then
		return false -- molette/boutons 4-5 (espacement) : au jeu ; la grille, aveugle, ne les voit pas
	end
	if not hit then
		return false
	end
	if not refresh() then
		return false
	end
	if hit.kind == "card" and hit.i then
		if button == 1 then
			drag = { slot = hit.slot, i = hit.i, x = x, y = y }
		else
			cycleCategory(hit.i)
		end
	elseif hit.kind == "tab" and button == 1 then
		if L.mode == "grid" then
			openTab(hit.tab ~= gtab and hit.tab or nil)
		else
			setPanelTab(hit.tab)
		end
	elseif hit.kind == "back" and button == 1 then
		openTab(nil)
	elseif hit.kind == "next" and button == 1 then
		onNextPage()
	end
	return true -- ne pas poser le blueprint sous la galerie
end

function widget:MouseRelease(x, y, button)
	local d = drag
	drag = nil
	if not d or button ~= 1 or not h then
		return false
	end
	local moved = math.abs(x - d.x) + math.abs(y - d.y) >= DRAG_MIN_PX
	local target = hitTest(x, y)
	local sameCard = target and target.kind == "card" and ((d.slot and target.slot == d.slot) or (not d.slot and target.i == d.i))
	if moved and not sameCard and L.mode == "grid" and gtab and target and target.kind == "card" and target.slot then
		moveSlot(gtab, d.slot, target.slot) -- glisser vers une autre case de l'onglet : ranger
	elseif sameCard or not moved then
		selectIndex(d.i) -- clic, meme avec un petit mouvement, tant qu'on relache sur la meme carte
		lastPerTab[currentView()] = d.i
	end
	return false
end

function widget:MouseWheel(up, value)
	if not open then
		return false
	end
	local alt, ctrl, _, shift = spGetModKeyState()
	if shift then
		return false
	end
	local now = spGetTimer()
	if lastWheel and spDiffTimers(now, lastWheel) < WHEEL_RATE_LIMIT then
		return true
	end
	lastWheel = now
	if not refresh() then
		return false
	end
	-- option « Molette pendant la pose » : choisir (Alt+molette tourne) ou tourner (Alt+molette choisit)
	local rotate = (wheelMode == "rotate") ~= (alt and true or false)
	if ctrl then
		stepTab(up and 1 or -1)
	elseif rotate then
		if h.facingFn then
			local arg = up and "inc" or "dec"
			h.facingFn("buildfacing", arg, { arg })
		end
	else
		stepInView(up and 1 or -1)
	end
	return true
end

function widget:Shutdown()
	pcall(restoreWrapper) -- en premier : la grille retrouve la souris quoi qu'il arrive ensuite
	gridMode = false
	if optionAdded and WG.options and WG.options.removeOption then
		pcall(WG.options.removeOption, OPTION_ID)
	end
	local ah = widgetHandler and widgetHandler.actionHandler
	if ah and ah.RemoveAction then
		pcall(ah.RemoveAction, ah, widget, "gridmenu_key", "pR")
		pcall(ah.RemoveAction, ah, widget, "gridmenu_category", "pR")
		pcall(ah.RemoveAction, ah, widget, "gridmenu_next_page", "pR")
	end
	if displayList then
		gl.DeleteList(displayList)
		displayList = nil
	end
	local hh = h or hook() -- le widget officiel peut deja etre ferme : alors 0
	local n = hh and #hh.list or 0
	mEcho(string.format(
		"[Galerie] stats reclassements=%d rangements=%d blueprints=%d dessin_ms=%.4f images=%d",
		stats.reclass, stats.moves, n, stats.frames > 0 and stats.drawMs / stats.frames or 0, stats.frames
	))
	-- le verrou n'est jamais efface : il expire seul (90 s), meme apres F11 en pleine partie
end

-- pour les tests (tests/galerie_test.py)
widget.__test = {
	hook = hook,
	gridHook = gridHook,
	upvalueDeep = upvalueDeep,
	autoCategory = autoCategory,
	parseName = parseName,
	setName = setName,
	category = category,
	cycleCategory = cycleCategory,
	tabLayout = tabLayout,
	signature = signature,
	galleryAlive = galleryAlive,
	getWheelMode = function()
		return wheelMode
	end,
	tr = function(...)
		return tr(...)
	end,
	getLanguage = function()
		return lang
	end,
	isMeasuring = function()
		return MEASURE
	end,
	getState = function()
		return { open = open, gridMode = gridMode, gtab = gtab, gpage = gpage, ptab = ptab, h = h }
	end,
}
