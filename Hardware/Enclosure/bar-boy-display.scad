// MOMO LABZ agent desk enclosure — prototype 0.2
// Units: millimetres. Measure your specific LCD before the final print.
// part = "body", "back", "stand", or "assembly".
part = "assembly";
$fn = 36;

outer_w = 100;
outer_h = 72;
outer_d = 28;
wall = 2.4;
front = 3;
screen_w = 74;
screen_h = 50;
screen_x = (outer_w - screen_w) / 2;
screen_y = (outer_h - screen_h) / 2;
fit = 0.35;

module body() {
    difference() {
        cube([outer_w, outer_h, outer_d]);
        translate([wall, wall, front])
            cube([outer_w - 2 * wall, outer_h - 2 * wall, outer_d + 1]);
        translate([screen_x, screen_y, -1])
            cube([screen_w, screen_h, front + 2]);
        // Pixel ventilation cuts at the top and bottom edges.
        for (x = [12:10:82]) {
            translate([x, 1, 12]) cube([5, wall + 1, 8]);
            translate([x, outer_h - wall - 1, 12]) cube([5, wall + 2, 8]);
        }
        // Right-side cable slot.
        translate([outer_w - wall - 1, 27, 10]) cube([wall + 2, 18, 10]);
    }
}

module back() {
    difference() {
        cube([outer_w - 2 * wall - fit, outer_h - 2 * wall - fit, 2]);
        for (x = [18:8:70])
            translate([x, 16, -1]) cube([4, 30, 4]);
    }
    // Friction ribs; lightly sand if your printer runs tight.
    translate([3, 3, 2]) cube([outer_w - 2 * wall - fit - 6, 1.2, 2]);
    translate([3, outer_h - 2 * wall - fit - 4.2, 2]) cube([outer_w - 2 * wall - fit - 6, 1.2, 2]);
}

module stand() {
    cube([80, 34, 4]);
    translate([8, 5, 4]) cube([8, 24, 22]);
    translate([64, 5, 4]) cube([8, 24, 22]);
    translate([8, 5, 22]) cube([64, 24, 4]);
}

if (part == "body") body();
if (part == "back") back();
if (part == "stand") stand();
if (part == "assembly") {
    body();
    translate([2 * outer_w, 0, 0]) back();
    translate([0, -45, 0]) stand();
}
