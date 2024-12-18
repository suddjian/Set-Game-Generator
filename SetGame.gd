extends Node

# features:
# number: 1, 2, 3
# shape: square, circle, triangle
# color: blue, yellow, purple
# fill: empty, partial, filled

# variants: 3

# constraint:
# there should be a solution where
# all variables are (different or same)
# in every row
# in every column

# wave function collapse algorithm to generate puzzles:
# Step 1: Populate the possibility space with superpositions
# Step 2: Pick a cell to collapse
# Step 3: Propagate the consequences of the collapse, following constraints
# Step 4: Repeat until all cells are collapsed.
# Step 5: Repeat for each feature, and zip the features up into one grid.
# Step 6: Scramble the grid so it's a puzzle.


# a particular feature is represented with an array of all the possibilities (variants)
# a cell in the puzzle has an array of possibilities for each feature.

var feature_names = [ "Number", "Shape", "Color", "Fill" ]

var grid = null

# a particular feature must be either all the same, or all different, for cells sharing a column.
var col_constraints = null
# same for cells sharing a row
var row_constraints = null

var result_grid = [
	[], [], [],
	[], [], [],
	[], [], [],
] # just feature ids


# the constraint codes
const DIFF = 0
const SAME = 1


@onready var node_grid_container: Node = $CenterContainer/GridContainer
@onready var node_col_constraints: Node = $ColConstraints
@onready var node_row_constraints: Node = $RowConstraints
@onready var button_undo: Button = $Sidebar/Undo
@onready var button_redo: Button = $Sidebar/Redo


var undo_redo := UndoRedo.new()

func _init():
	init_grid()
	init_constraints()


func _ready():
	print('cols', col_constraints, ' rows', row_constraints)

	for button in node_grid_container.get_children():
		button.pressed.connect(collapse.bind(button.get_index()))
	update_ui()


func update_ui():

	for i in 9:
		var name = "Button%d" % i
		var button: Button = node_grid_container.get_node(name)
		var options = grid[i]["options"]
		var result = result_grid[i]
		button.text = str(options) + "\n" + str(result)

	for i in 3:
		var name = "Label%d" % i
		var collabel: Label = node_col_constraints.get_node(name)
		collabel.text = "same" if col_constraints[i] else "diff"

		var rowlabel: Label = node_row_constraints.get_node(name)
		rowlabel.text = "same" if row_constraints[i] else "diff"

	button_undo.disabled = !undo_redo.has_undo()
	button_redo.disabled = !undo_redo.has_redo()


func init_grid():

	grid = []

	for y in 3:
		for x in 3:
			var cell = {
				"x": x,
				"y": y,
				"i": y*3+x,
				"options": [0, 1, 2],
			}
			cell["options"].shuffle()
			grid.append(cell)


func init_constraints():
	row_constraints = [DIFF, SAME, DIFF]
	col_constraints = [DIFF, SAME, DIFF]
	row_constraints.shuffle()
	col_constraints.shuffle()
	# Also all-same and all-diff,
	# but I don't think those are really worth including.


func add_result():
	for i in len(grid):
		result_grid[i].append(grid[i]["options"][0])
	update_ui()


func generate_puzzle():
	for feature in feature_names:
		init_constraints()
		init_grid()
		wfc()
		add_result()
	result_grid.shuffle()
	update_ui()


func are_constraints_solvable(col_con, row_con):

	# This is incomplete.
	# SAME SAME DIFF, DIFF DIFF DIFF falsely returns true.
	# But it's also not needed.
	# It helped me find a method for generating only valid constraints.

	var map = [
		[ -1, -1, -1 ],
		[ -1, -1, -1 ],
		[ -1, -1, -1 ],
	]

	# each constraint has a region.
	# algorithm to detect conflicting regions:
	# 1: map SAME regions.
	# 	1a: combine intersecting SAME regions into one region
	# 2: check that each DIFF constraint does not cross the same SAME region twice.

	var same_rules := []
	var diff_rules := []

	for x in len(col_con):
		var set = [[x, 0], [x, 1], [x, 2]]
		if col_con[x] == SAME:
			same_rules.append(set)
		else:
			diff_rules.append(set)

	for y in len(row_con):
		var set = [[0, y], [1, y], [2, y]]
		if row_con[y] == SAME:
			same_rules.append(set)
		else:
			diff_rules.append(set)


	# combine any intersecting same regions, to make a map labeled by region
	var regions = []
	var region_count = 0
	for coord_set in same_rules:
		var intersections = []
		var region = [] # array of coordinates
		var id = len(regions)
		for coord in coord_set:
			var x = coord[0]
			var y = coord[1]
			if map[y][x] != -1 and not intersections.has(map[y][x]):
				# there is an overlapping same region
				intersections.append(map[y][x])
			map[y][x] = id
			region.append([x, y])
		for intersection in intersections:
			print("intersection ", intersection, " ", str(regions[intersection]))
			region.append_array(regions[intersection])
			for coord in regions[intersection]:
				map[coord[1]][coord[0]] = id

		regions.append(region)
		print("\n".join(map) + "\n")


	# check that each diff rule doesn't intersect the same region twice.
	for coord_set in diff_rules:
		var seen := []
		for coord in coord_set:
			var x = coord[0]
			var y = coord[1]
			var id = map[y][x]
			if id == -1:
				continue
			if seen.has(map[y][x]):
				print("intersection at %d, %d" % [x, y])
				return false
			seen.append(id)

	print("constraints ok")
	print("\n".join(map) + "\n")
	return true


func is_grid_valid():
	for cell in grid:
		if len(cell["options"]) == 0:
			return false
	return true


func is_fully_collapsed():
	for cell in grid:
		if len(cell["options"]) != 1:
			return false
	return true


func wfc():

	var grid_backtrack := []
	var trace := [grid[4].duplicate(true)]

	while not is_fully_collapsed() and len(trace):

		grid_backtrack.append(grid.duplicate(true))

		var frame = trace.back()
		var cell = grid[frame["i"]]

		var collapsed = [frame["options"].pop_back()]
		cell["options"] = collapsed
		propagate_constraints(cell)

		if is_grid_valid():
			var lowest_entropy = find_lowest_entropy_cell()
			if lowest_entropy:
				trace.append(lowest_entropy.duplicate(true))
		else:
			grid = grid_backtrack.pop_back()
			if len(frame["options"]) <= 0:
				# This branch failed.
				# We can go back and try different options
				# on previous frames, if there are any.
				trace.pop_back()

	update_ui()




func find_lowest_entropy_cell():
	# find lowest entropy cells (cells with least options)
	var lowest = null
	var lowest_entropy = -1
	for cell in grid:
		var entropy := len(cell["options"])
		if entropy == 1:
			continue
		if lowest == null or entropy < lowest_entropy:
			lowest = cell
			lowest_entropy = entropy
	return lowest


func pick_lowest_entropy():
	# find lowest entropy cells (cells with least options)
	var low_ent := [] # indexes
	var lowest_ent := -1
	for i in len(grid):
		var cell = grid[i]
		var entropy := len(cell["options"])
		if entropy == 1:
			continue
		elif entropy < lowest_ent or lowest_ent == -1:
			low_ent = [i]
			lowest_ent = entropy
		elif entropy == lowest_ent:
			low_ent.append(i)

	if len(low_ent) == 0:
		return null

	var picked = low_ent.pick_random()
	print("picked lowest entropy ", picked)
	collapse(picked)


func collapse(index: int):
	var cached_grid = grid.duplicate(true)

	undo_redo.create_action("collapse %d" % index)
	undo_redo.add_undo_method(func(): grid = cached_grid)
	undo_redo.add_do_method(func(): do_collapse(index))
	undo_redo.commit_action()

	if not is_grid_valid():
		print("invalid state, undoing")
		undo_redo.undo()
	else:
		update_ui()



func do_collapse(index: int):
	# collapse by removing a single option, and propagating the constraints.

	var cell = grid[index]
	var options: Array = cell["options"]
	if len(options) <= 1:
		return

	# there are multiple candidate options to choose,
	var to_remove := randi_range(0, len(options) - 1)
	var collapsed: Array = options.duplicate(true)
	collapsed.remove_at(to_remove)

	cell["options"] = collapsed

	propagate_constraints(cell)



func propagate_constraints(cell):
	var cx = cell["x"]
	var cy = cell["y"]
	var cells_to_repropagate = []

	var cell_options: Array = cell["options"]

	var propagate_to_cell = func (to_cell, constraint):
		if to_cell == cell:
			return

#		print("propagating from %d %d to %d %d" % [cx, cy, to_cell["x"], to_cell["y"]])

		# this is where the change of one cell affects another
		var options = to_cell["options"]
		var filtered = []

		if constraint == SAME:
			for opt in options:
				if cell_options.has(opt):
					filtered.append(opt)
		else: # DIFF
			for opt in options:
				# all other cells must only contain options that can differ from
				# some option in the propagating cell
				if len(cell_options) > 1 or cell_options[0] != opt:
					filtered.append(opt)

		to_cell["options"] = filtered
		if len(options) != len(filtered):
			cells_to_repropagate.append(to_cell)

	var col_constraint = col_constraints[cx]

	for y in 3:
		propagate_to_cell.call(grid[y*3+cx], col_constraint)

	var row_constraint = row_constraints[cy]

	for x in 3:
		propagate_to_cell.call(grid[cy*3+x], row_constraint)

	for cell2 in cells_to_repropagate:
		propagate_constraints(cell2)




















func reset_constraints():
	init_constraints()
	init_grid()
	undo_redo.clear_history()
	update_ui()


func reset_grid():
	init_grid()
	undo_redo.clear_history()
	update_ui()


func undo():
	undo_redo.undo()
	update_ui()


func redo():
	undo_redo.redo()
	update_ui()
