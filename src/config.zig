pub const Config = struct {
    tick_rate: usize = 10,
    pop_per_housing: usize = 5,

    starting_food: u32 = 0,
    starting_wood: u32 = 0,

    training: struct {
        worker_ticks: u32 = 200,
        soldier_ticks: u32 = 300,
        worker_food_cost: u32 = 0,
        soldier_food_cost: u32 = 40,
        soldier_wood_cost: u32 = 20,
    } = .{},

    economy: struct {
        tree_total_yield: u16 = 100,
        deer_total_yield: u16 = 100,
        farm_yield_total: u16 = 250,
        carry_capacity: u16 = 10,
        wood_gather_rate: u32 = 2,
        food_gather_rate: u32 = 3,
        farm_gather_rate: u32 = 4,
        deer_hunt_radius: usize = 12,
        hunt_drift_repath: usize = 3,
        deer_rot_rate: u32 = 1,
        grove_scan_radius: usize = 8,
        resow_wood_cost: u32 = 60,
        dropoff_adjacent: bool = true,
    } = .{},

    selection: struct {
        max_selected: usize = 128,
    } = .{},

    glyphs: struct {
        worker: []const u8 = "w",
        soldier: []const u8 = "s",
        deer: []const u8 = "d",
        dead_deer: []const u8 = "x",
        town_center: []const u8 = "C",
        house: []const u8 = "H",
        barracks: []const u8 = "B",
        farm: []const u8 = "F",
        drop_pile: []const u8 = "P",
        tree: []const u8 = "T",
        water: []const u8 = "~",
        grass: []const u8 = " ",
    } = .{},

    labels: struct {
        town_center: []const u8 = "TC",
        house: []const u8 = "House",
        barracks: []const u8 = "Barracks",
        farm: []const u8 = "Farm",
        drop_pile: []const u8 = "Drop",
        worker: []const u8 = "Worker",
        soldier: []const u8 = "Soldier",
        deer: []const u8 = "Deer",
        grass: []const u8 = "Grass",
        tree: []const u8 = "Forest",
        water: []const u8 = "Water",
    } = .{},

    ui_text: struct {
        tile_label: []const u8 = "Tile:",
        sel_label: []const u8 = "Sel:",
        hp_label: []const u8 = " HP:",
        build_label: []const u8 = " Build:",
        pop_label: []const u8 = "Pop:",
        w_label: []const u8 = " W:",
        s_label: []const u8 = " S:",
        coord_help: []const u8 = "Enter=goto Esc=cancel",
    } = .{},

    map_dims: struct {
        default_width: u16 = 80,
        default_height: u16 = 40,
        max_width: usize = 200,
        max_height: usize = 100,
        min_term_width: u16 = 20,
        min_term_height: u16 = 15,
    } = .{},
    entity_limits: struct {
        max_path: usize = 256,
        max_units: usize = 128,
        max_buildings: usize = 32,
        max_wildlife: usize = 256,
        max_blocked: usize = 256,
    } = .{},
    unit_hp: struct {
        worker: u16 = 50,
        soldier: u16 = 100,
    } = .{},
    wildlife_hp: struct {
        deer: u16 = 25,
    } = .{},

    building_hp: struct {
        town_center: u16 = 500,
        house: u16 = 200,
        barracks: u16 = 300,
        farm: u16 = 100,
        drop_pile: u16 = 100,
    } = .{},

    deer: struct {
        wander_interval: usize = 15,
        near_tc_percent: usize = 15,
        min_near_tc: usize = 1,
        spawn_spread: usize = 12,
        spawn_offset: usize = 6,
        scatter_min_dist: usize = 2,
        spawn_seed_offset: u64 = 999,
        area_divisor: usize = 300,
        min_count: usize = 12,
        seed_mult_tick: u64 = 31,
        seed_mult_idx: u64 = 17,
        scatter_herd_count: usize = 10,
        herd_size: usize = 6,
        herd_radius: usize = 3,
        tc_herd_offset: usize = 8,
        herd_min_spacing: usize = 12,
        herd_wander_radius: usize = 5,
    } = .{},

    map_gen: struct {
        player_tc_x_pct: usize = 15,
        enemy_tc_x_pct: usize = 85,
        // TC clear radius: randomized per game
        tc_clear_min: usize = 6,
        tc_clear_max: usize = 10,
        // Sector size: randomized per game (smaller = more clusters, larger = sparser)
        sector_size_min: usize = 20,
        sector_size_max: usize = 36,
        // Biome density: % of sectors that become each type (randomized per game)
        tree_density_min: usize = 18,
        tree_density_max: usize = 42,
        water_density_min: usize = 5,
        water_density_max: usize = 20,
        // Cluster sizes: randomized within range
        tree_cluster_min: usize = 10,
        tree_cluster_max_div: usize = 40,
        water_cluster_min: usize = 10,
        water_cluster_max_div: usize = 50,
        // TC buffer zones
        tree_tc_buffer: usize = 2,
        water_tc_buffer: usize = 4,
        cluster_tc_buffer: usize = 1,
        cluster_frontier_cap: usize = 600,
        corridor_width: usize = 2,
        // Scattered trees: % of grass tiles that get lone trees (randomized per game)
        scatter_tree_min: usize = 1,
        scatter_tree_max: usize = 6,
        // Guaranteed starting grove near each TC
        start_grove_count: usize = 15,
        start_grove_offset: usize = 2,
    } = .{},

    ui: struct {
        drawer_height: u16 = 5,
        label_width: u16 = 3,
        min_drawer_width: u16 = 10,
        right_panel_offset: u16 = 20,
        coord_input_offset: u16 = 22,
        seconds_per_minute: usize = 60,
        notif_lifetime: usize = 50,
    } = .{},
    timing: struct {
        tick_period_ns: u64 = 100_000_000,
        resize_poll_interval_ns: u64 = 10_000_000,
        frame_sleep_ns: u64 = 1_000_000,
        repath_cooldown_ticks: usize = 3,
    } = .{},

    colors: struct {
        drawer_border: [3]u8 = .{ 80, 80, 80 },
        drawer_label: [3]u8 = .{ 120, 120, 120 },
        drawer_val: [3]u8 = .{ 220, 220, 220 },
        drawer_cyan: [3]u8 = .{ 0, 200, 200 },
        drawer_red: [3]u8 = .{ 210, 80, 80 },
        drawer_brown: [3]u8 = .{ 170, 130, 60 },
        drawer_dim: [3]u8 = .{ 100, 100, 80 },
        drawer_yellow: [3]u8 = .{ 255, 255, 100 },

        header_dim: [3]u8 = .{ 140, 140, 140 },
        header_active: [3]u8 = .{ 255, 255, 255 },
        cursor_selected_bg: [3]u8 = .{ 40, 40, 40 },
        cursor_reversed_fg: [3]u8 = .{ 20, 20, 20 },
        help_bg: [3]u8 = .{ 45, 55, 75 },
        help_border: [3]u8 = .{ 120, 140, 180 },
        help_body: [3]u8 = .{ 200, 200, 200 },
        building_tile: [3]u8 = .{ 200, 200, 200 },

        tile_grass: [3]u8 = .{ 30, 30, 30 },
        tile_tree: [3]u8 = .{ 30, 130, 30 },
        tile_tree_depleted: [3]u8 = .{ 110, 210, 110 },
        tile_water: [3]u8 = .{ 40, 90, 180 },

        wildlife_deer_depleted: [3]u8 = .{ 210, 175, 120 },
        farm_food_depleted: [3]u8 = .{ 170, 220, 220 },

        player_unit_full: [3]u8 = .{ 0, 200, 200 },
        player_unit_damaged: [3]u8 = .{ 150, 235, 235 },
        player_building_full: [3]u8 = .{ 0, 170, 170 },
        player_building_damaged: [3]u8 = .{ 140, 220, 220 },
        player_unbuilt: [3]u8 = .{ 140, 220, 220 },

        enemy_unit_full: [3]u8 = .{ 210, 40, 40 },
        enemy_unit_damaged: [3]u8 = .{ 255, 140, 140 },
        enemy_building_full: [3]u8 = .{ 180, 30, 30 },
        enemy_building_damaged: [3]u8 = .{ 255, 120, 120 },
        enemy_unbuilt: [3]u8 = .{ 255, 120, 120 },

        neutral_full: [3]u8 = .{ 140, 95, 35 },
        neutral_damaged: [3]u8 = .{ 220, 185, 140 },
        neutral_unbuilt: [3]u8 = .{ 255, 230, 100 },

        notif_info: [3]u8 = .{ 180, 180, 180 },
        notif_good: [3]u8 = .{ 100, 220, 100 },
        notif_bad: [3]u8 = .{ 220, 100, 100 },
    } = .{},
};

pub fn default() Config {
    return .{};
}
