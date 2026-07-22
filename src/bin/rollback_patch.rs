use std::path::Path;
use binary_patcher::rollback;

fn main() {
    let result = rollback::rollback_bundle(&Path::new("."));

    if let Err(e) = result {
        eprintln!("错误: {e}");
        pause_if_needed();
        std::process::exit(1);
    }

    pause_if_needed();
}

fn pause_if_needed() {
    if !atty::is(atty::Stream::Stdin) {
        return;
    }
    println!("\n按 Enter 键退出...");
    let _ = std::io::stdin().read_line(&mut String::new());
}
