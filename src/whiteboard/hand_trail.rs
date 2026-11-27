use std::{
    collections::HashMap,
    time::{Duration, Instant},
};
use tiny_skia::{LineCap, LineJoin, Paint, PathBuilder, PixmapMut, Stroke, Transform};

const TRAIL_LIFE: Duration = Duration::from_millis(1500);
const MAX_POINTS: usize = 240;

#[derive(Default)]
pub(super) struct Trails {
    points: HashMap<String, Vec<(f32, f32, Instant)>>,
}

impl Trails {
    pub(super) fn push(&mut self, key: &str, x: f32, y: f32) {
        let trail = self.points.entry(key.to_owned()).or_default();
        if let Some(&(lx, ly, _)) = trail.last() {
            if (lx - x).abs() < 1.0 && (ly - y).abs() < 1.0 {
                return;
            }
        }
        trail.push((x, y, Instant::now()));
        if trail.len() > MAX_POINTS {
            let excess = trail.len() - MAX_POINTS;
            trail.drain(..excess);
        }
    }

    pub(super) fn draw(&mut self, pixmap: &mut PixmapMut) {
        let now = Instant::now();
        self.points.retain(|_, trail| {
            trail.retain(|p| now.duration_since(p.2) < TRAIL_LIFE);
            !trail.is_empty()
        });
        let stroke = Stroke {
            width: 6.0,
            line_cap: LineCap::Round,
            line_join: LineJoin::Round,
            ..Default::default()
        };
        for trail in self.points.values() {
            for pair in trail.windows(2) {
                let (x0, y0, _) = pair[0];
                let (x1, y1, t1) = pair[1];
                let life = 1.0
                    - now.duration_since(t1).as_secs_f32() / TRAIL_LIFE.as_secs_f32();
                if life <= 0.0 {
                    continue;
                }
                let mut pb = PathBuilder::new();
                pb.move_to(x0, y0);
                pb.line_to(x1, y1);
                let Some(path) = pb.finish() else {
                    continue;
                };
                let mut paint = Paint::default();
                paint.anti_alias = true;
                // Buffer is BGRA: HoneyWorld purple #582B7F.
                paint.set_color_rgba8(0x7F, 0x2B, 0x58, (life * 220.0) as u8);
                pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), None);
            }
        }
    }
}
