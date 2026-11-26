use std::{collections::HashMap, sync::Mutex};
use windows::{
    core::BOOL,
    Win32::{
        Foundation::{HWND, LPARAM, LRESULT, RECT, WPARAM},
        System::Threading::GetCurrentProcessId,
        UI::{
            Shell::{DefSubclassProc, RemoveWindowSubclass, SetWindowSubclass},
            WindowsAndMessaging::{
                EnumWindows, GetClientRect, GetWindowRect, GetWindowTextW,
                GetWindowThreadProcessId, WMSZ_BOTTOM, WMSZ_BOTTOMLEFT, WMSZ_LEFT, WMSZ_RIGHT, WMSZ_TOP, WMSZ_TOPLEFT, WMSZ_TOPRIGHT, WM_NCDESTROY,
                WM_SIZING,
            },
        },
    },
};

const SUBCLASS_ID: usize = 0x48_414E_44;

#[derive(Clone, Copy, Default)]
struct Lock {
    hwnd: isize,
    ratio: f64,
    extra_w: i32,
    extra_h: i32,
}

lazy_static::lazy_static! {
    static ref LOCKS: Mutex<HashMap<i32, Lock>> = Mutex::new(HashMap::new());
}

struct Search {
    token: Vec<u16>,
    found: HWND,
}

unsafe extern "system" fn find_by_title(hwnd: HWND, lparam: LPARAM) -> BOOL {
    let search = &mut *(lparam.0 as *mut Search);
    let mut pid = 0u32;
    GetWindowThreadProcessId(hwnd, Some(&mut pid as *mut u32));
    if pid != GetCurrentProcessId() {
        return BOOL(1);
    }
    let mut buf = [0u16; 256];
    let len = GetWindowTextW(hwnd, &mut buf) as usize;
    if len > 0 && buf[..len] == search.token[..] {
        search.found = hwnd;
        return BOOL(0);
    }
    BOOL(1)
}

fn frame_extra(hwnd: HWND) -> (i32, i32) {
    let mut w = RECT::default();
    let mut c = RECT::default();
    unsafe {
        if GetWindowRect(hwnd, &mut w).is_err() || GetClientRect(hwnd, &mut c).is_err() {
            return (0, 0);
        }
    }
    (
        (w.right - w.left) - (c.right - c.left),
        (w.bottom - w.top) - (c.bottom - c.top),
    )
}

fn lock_for(hwnd: HWND) -> Option<Lock> {
    let locks = LOCKS.lock().ok()?;
    locks.values().find(|l| l.hwnd == hwnd.0 as isize).copied()
}

unsafe extern "system" fn subclass_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
    _id: usize,
    _data: usize,
) -> LRESULT {
    if msg == WM_SIZING {
        if let Some(lock) = lock_for(hwnd) {
            if lock.ratio > 0.0 && lparam.0 != 0 {
                apply(&mut *(lparam.0 as *mut RECT), wparam.0 as u32, &lock);
                return LRESULT(1);
            }
        }
    } else if msg == WM_NCDESTROY {
        let _ = RemoveWindowSubclass(hwnd, Some(subclass_proc), SUBCLASS_ID);
        if let Ok(mut locks) = LOCKS.lock() {
            locks.retain(|_, l| l.hwnd != hwnd.0 as isize);
        }
    }
    DefSubclassProc(hwnd, msg, wparam, lparam)
}

fn apply(rect: &mut RECT, edge: u32, lock: &Lock) {
    let (frame_w, frame_h) = frame_extra(HWND(lock.hwnd as _));
    let extra_w = frame_w + lock.extra_w;
    let extra_h = frame_h + lock.extra_h;
    let w = (rect.right - rect.left - extra_w).max(1) as f64;
    let h = (rect.bottom - rect.top - extra_h).max(1) as f64;
    let (new_w, new_h) = match edge {
        WMSZ_LEFT | WMSZ_RIGHT => (w, w / lock.ratio),
        WMSZ_TOP | WMSZ_BOTTOM => (h * lock.ratio, h),
        _ => {
            if w / h > lock.ratio {
                (h * lock.ratio, h)
            } else {
                (w, w / lock.ratio)
            }
        }
    };
    let total_w = new_w.round() as i32 + extra_w;
    let total_h = new_h.round() as i32 + extra_h;
    match edge {
        WMSZ_TOPLEFT => {
            rect.left = rect.right - total_w;
            rect.top = rect.bottom - total_h;
        }
        WMSZ_TOPRIGHT | WMSZ_TOP => {
            rect.right = rect.left + total_w;
            rect.top = rect.bottom - total_h;
        }
        WMSZ_BOTTOMLEFT | WMSZ_LEFT => {
            rect.left = rect.right - total_w;
            rect.bottom = rect.top + total_h;
        }
        _ => {
            rect.right = rect.left + total_w;
            rect.bottom = rect.top + total_h;
        }
    }
}

pub fn bind(window_id: i32, token: &str) -> bool {
    let mut search = Search {
        token: token.encode_utf16().collect(),
        found: HWND::default(),
    };
    unsafe {
        let _ = EnumWindows(Some(find_by_title), LPARAM(&mut search as *mut Search as isize));
    }
    if search.found.is_invalid() {
        return false;
    }
    let hwnd = search.found;
    if unsafe { !SetWindowSubclass(hwnd, Some(subclass_proc), SUBCLASS_ID, 0).as_bool() } {
        return false;
    }
    match LOCKS.lock() {
        Ok(mut locks) => {
            let entry = locks.entry(window_id).or_default();
            entry.hwnd = hwnd.0 as isize;
            true
        }
        Err(_) => false,
    }
}

pub fn set(window_id: i32, ratio: f64, extra_w: i32, extra_h: i32) {
    if let Ok(mut locks) = LOCKS.lock() {
        if let Some(lock) = locks.get_mut(&window_id) {
            lock.ratio = ratio;
            lock.extra_w = extra_w;
            lock.extra_h = extra_h;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_ratio_when_dragging_corner() {
        let lock = Lock {
            hwnd: 0,
            ratio: 16.0 / 9.0,
            extra_w: 0,
            extra_h: 40,
        };
        let mut r = RECT {
            left: 0,
            top: 0,
            right: 1600,
            bottom: 1000,
        };
        apply(&mut r, windows::Win32::UI::WindowsAndMessaging::WMSZ_BOTTOMRIGHT, &lock);
        let w = (r.right - r.left) as f64;
        let h = (r.bottom - r.top - 40) as f64;
        assert!((w / h - 16.0 / 9.0).abs() < 0.01);
    }
}
