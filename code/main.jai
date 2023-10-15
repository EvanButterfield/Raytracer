main :: () {
    aspect_ratio :: 16.0 / 9.0;
    
    width: s32 = 400;
    height: s32 = cast(s32)(width / aspect_ratio);
    samples: s32 : 100;
    max_depth: s32 : 50;
    
    viewport_height := 2.0;
    viewport_width := aspect_ratio * viewport_height;
    focal_length :: 1.0;
    
    origin: Vector3 : .{0, 0, 0};
    horizontal: Vector3 = .{viewport_width, 0, 0};
    vertical: Vector3 = .{0, viewport_height, 0};
    lower_left_corner := origin - horizontal/2 - vertical/2 - .{0, 0, focal_length};
    
    window := create_window(width, height, "Raytracer");
    window_width, window_height := get_render_dimensions(window);
    set_render_target(window);
    
    min_dist := 0.001;
    max_dist := FLOAT32_INFINITY;
    
    bitmap: Bitmap;
    bitmap_alloc(*bitmap, width, height, .RGB8);
    
    material_ground := create_lambertian(.{0.8, 0.8, 0});
    material_center := create_lambertian(.{0.7, 0.3, 0.3});
    material_left := create_metal(.{0.8, 0.8, 0.8}, 0.3);
    material_right := create_metal(.{0.8, 0.6, 0.2}, 1);
    
    spheres: [..]Sphere;
    array_add(*spheres, .{.{0, -100.5, -1}, 100, material_ground});
    array_add(*spheres, .{.{0, 0, -1}, 0.5, material_center});
    array_add(*spheres, .{.{-1, 0, -1}, 0.5, material_left});
    array_add(*spheres, .{.{1, 0, -1}, 0.5, material_right});
    
    for y:0..(height - 1) {
        print("Scanlines remaining: %\n", height - y);
        for x:0..(width - 1) {
            color: Vector3;
            
            for 0..samples {
                u := (x + random_get_zero_to_one_open()) / (width - 1);
                v := (y + random_get_zero_to_one_open()) / (height - 1);
                ray: Ray = .{origin, lower_left_corner + u*horizontal + v*vertical - origin};
                
                color += ray_color(ray, spheres, min_dist, max_dist, max_depth);
            }
            
            color *= 1.0 / samples;
            
            ir := cast(u8)(256 * clamp(color.x, 0, 0.999));
            ig := cast(u8)(256 * clamp(color.y, 0, 0.999));
            ib := cast(u8)(256 * clamp(color.z, 0, 0.999));
            
            index := (x + y*width)*3;
            bitmap.data[index] = ir;
            bitmap.data[index + 1] = ig;
            bitmap.data[index + 2] = ib;
        }
    }
    
    texture: Texture;
    texture_load_from_bitmap(*texture, *bitmap);
    
    last_time: float64;
    quit := false;
    while !quit {
        time := get_time();
        delta_time := cast(float)(time - last_time);
        // print("%\n", delta_time);
        last_time = time;
        
        update_window_events();
        for get_window_resizes() {
            update_window(it.window);
            
            if it.window == window {
                window_width = it.width;
                window_height = it.height;
                
                // width = window_width;
                // height = cast(s32)(width / aspect_ratio);
                // deinit(*bitmap);
                // bitmap_alloc(*bitmap, width, height, .RGB8);
            }
        }
        
        for events_this_frame {
            if it.type == .QUIT {
                quit = true;
                break;
            }
            
            if it.type == .KEYBOARD {
                if it.key_code == .ESCAPE && it.key_pressed {
                    quit = true;
                    break;
                }
            }
        }
        
        clear_render_target(0.1, 0.1, 0.1, 1);
        
        set_shader_for_images(*texture);
        immediate_begin();
        immediate_quad(window_width/2.0 - width/2.0, window_height/2.0 + height/2.0,
                       window_width/2.0 + width/2.0, window_height/2.0 - height/2.0, .{1, 1, 1, 1});
        immediate_flush();
        
        swap_buffers(window);
        
        reset_temporary_storage();
    }
}

hit_spheres :: (ray: Ray, spheres: []Sphere, min_dist: float, max_dist: float, out_record: *Hit_Record) -> bool {
    record: Hit_Record;
    
    hit_anything := false;
    closest_so_far := max_dist;
    
    for spheres {
        if hit_sphere(ray, it, min_dist, closest_so_far, *record) {
            hit_anything = true;
            closest_so_far = record.t;
            <<out_record = record;
        }
    }
    
    return hit_anything;
}

hit_sphere :: (ray: Ray, sphere: Sphere, min_dist: float, max_dist: float, out_record: *Hit_Record) -> bool {
    oc := ray.origin - sphere.center;
    a := dot(ray.direction, ray.direction);
    half_b := dot(ray.direction, oc);
    c := dot(oc, oc) - sphere.radius*sphere.radius;
    
    discriminant := half_b*half_b - a*c;
    if discriminant < 0 {
        return false;
    }
    
    sqrtd := sqrt(discriminant);
    root := (-half_b - sqrtd) / a;
    if root < min_dist || root > max_dist {
        root = (-half_b + sqrtd) / a;
        if root < min_dist || root > max_dist {
            return false;
        }
    }
    
    out_record.t = root;
    out_record.hit_point = ray_at(ray, out_record.t);
    out_record.material = sphere.material;
    outward_normal := (out_record.hit_point - sphere.center) / sphere.radius;
    hit_record_set_face_normal(out_record, ray, outward_normal);
    
    return true;
}

ray_color :: (ray: Ray, spheres: []Sphere, min_dist: float, max_dist: float, depth: s32) -> Vector3 {
    if depth <= 0 {
        return .{0, 0, 0};
    }
    
    record: Hit_Record;
    if hit_spheres(ray, spheres, min_dist, max_dist, *record) {
        did_scatter := false;
        scattered: Ray;
        attenuation: Vector3;
        if record.material.type == {
            case .METAL;
            did_scatter = scatter_metal(record.material, ray, record, *scattered, *attenuation);
            
            case .LAMBERTIAN;
            did_scatter = scatter_lambertian(record.material, ray, record, *scattered, *attenuation);
        }
        
        if did_scatter {
            result := attenuation * ray_color(scattered, spheres, min_dist, max_dist, depth - 1);
            return result;
        }
        
        return .{0, 0, 0};
    }
    
    unit_direction := unit_vector(ray.direction);
    t := 0.5 * (unit_direction.y + 1);
    result := (1 - t) * Vector3.{1, 1, 1} + t * Vector3.{0.5, 0.7, 1};
    return result;
}

scatter_metal :: (material: Material, ray: Ray, record: Hit_Record, scattered: *Ray, attenuation: *Vector3) -> bool {
    reflected := vector3_reflect(unit_vector(ray.direction), record.normal);
    
    // NOTE(evan): We don't want to calculate random_in_unit_sphere if fuzz is 0
    fuzz_direction: Vector3 = ---;
    if material.fuzz > 0 {
        fuzz_direction = material.fuzz*random_in_unit_sphere();
    }
    else {
        fuzz_direction = .{};
    }
    
    <<scattered = .{record.hit_point, reflected + fuzz_direction};
    <<attenuation = material.albedo;
    
    result := dot(scattered.direction, record.normal) > 0;
    return result;
}

create_metal :: (albedo: Vector3, fuzz: float) -> Material {
    material: Material = .{.METAL, albedo, fuzz};
    return material;
}

scatter_lambertian :: (material: Material, ray: Ray, record: Hit_Record, scattered: *Ray, attenuation: *Vector3) -> bool {
    scatter_direction := record.normal + unit_vector(random_in_unit_sphere());
    
    if vector3_near_zero(scatter_direction) {
        scatter_direction = record.normal;
    }
    
    <<scattered = .{record.hit_point, scatter_direction};
    <<attenuation = material.albedo;
    return true;
}

create_lambertian :: (albedo: Vector3) -> Material {
    material: Material = .{.LAMBERTIAN, albedo, 0};
    return material;
}

Material :: struct {
    type: Material_Type;
    
    // LAMBERTIAN, METAL
    albedo: Vector3;
    
    // METAL
    fuzz: float;
}

Material_Type :: enum {
    METAL;
    LAMBERTIAN;
}

hit_record_set_face_normal :: (record: *Hit_Record, ray: Ray, outward_normal: Vector3) {
    record.front_face = dot(ray.direction, outward_normal) < 0;
    record.normal = ifx record.front_face then outward_normal else -outward_normal;
}

Hit_Record :: struct {
    hit_point: Vector3;
    normal: Vector3;
    t: float;
    front_face: bool;
    material: Material;
}

Sphere :: struct {
    center: Vector3;
    radius: float;
    material: Material;
}

ray_at :: (ray: Ray, t: float) -> Vector3 {
    result := ray.origin + ray.direction*t;
    return result;
}

Ray :: struct {
    origin: Vector3;
    direction: Vector3;
}

random_in_unit_sphere :: () -> Vector3 {
    while true {
        p: Vector3 = .{random_get_within_range(-1, 1), random_get_within_range(-1, 1), random_get_within_range(-1, 1)};
        if length_squared(p) >= 1 continue;
        return p;
    }
}

vector3_reflect :: (vector: Vector3, normal: Vector3) -> Vector3 {
    result := vector - 2*dot(vector, normal)*normal;
    return result;
}

vector3_near_zero :: (vector: Vector3) -> bool {
    s :: 0.00000001;
    result := (abs(vector.x) < s) && (abs(vector.y) < s) && (abs(vector.z) < s);
    return result;
}

DEG_TO_RAD :: PI/180.0;

#import "Basic";
#import "File";
#import "Math";
#import "Random";

#import "Simp";
#import "Window_Creation";
#import "Input";