//
//  MainViewController.swift
//  FaceAnimation_tensorflowlite
//
//  Created by zhangerbing on 2021/9/27.
//

import UIKit
import RxSwift
import RxCocoa
import Photos
import NSObject_Rx

class MainViewController: UIViewController, StoryboardInitializable {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var tableView: UITableView!
    
    var viewModel: MainViewModel!
    
    private var videoUrl: URL?
    
    // MARK: - view life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
    }
    
    private func setupUI() {
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.tableFooterView = UIView()
        
        logInfo("准备就绪")
    }
    
    private func bindViewModel() {
        viewModel.image.bind(to: imageView.rx.image).disposed(by: rx.disposeBag)
        
        viewModel.video.subscribe(onNext: { [weak self] url in
            self?.videoUrl = url
            PlayUtil.shared.play(url: url, on: self?.imageView)
        }, onError: { [weak self] error in
            self?.logInfo(error.localizedDescription)
        }).disposed(by: rx.disposeBag)
        
        viewModel.list.bind(to: tableView.rx.items(cellIdentifier: "cell", cellType: MainTableViewCell.self)) { _, title, cell in
            cell.titleLabel.text = title
        }.disposed(by: rx.disposeBag)
     
        tableView.rx.modelSelected(String.self)
            .bind(to: viewModel.execute)
            .disposed(by: rx.disposeBag)
        
        tableView.rx.modelSelected(String.self)
            .filter{ title in title != "开始执行" }
            .subscribe(onNext: { [weak self] title in
                self?.handle(title: title)
            })
            .disposed(by: rx.disposeBag)
        
        tableView.rx.itemSelected.subscribe(onNext: { [weak self] index in
            self?.tableView.deselectRow(at: index, animated: true)
        }).disposed(by: rx.disposeBag)
    }
}
 
private extension MainViewController {
    
    func handle(title: String) {
        switch title {
        case "保存到相册":
            AlbumUtils.save(url: videoUrl).subscribe(onCompleted: {
                self.logInfo("保存成功")
            }, onError: { error in
                self.logInfo("保存失败:" + error.localizedDescription)
            }).disposed(by: rx.disposeBag)
        case "重播":
            guard let url = videoUrl else {
                logInfo("没有可以播放的视频")
                return
            }
            PlayUtil.shared.play(url: url, on: self.imageView)
        default:
            break
        }
    }
}

extension MainViewController {
    private func logInfo(_ info: String) {
        let prefix = "输出台:\n\n"
        textView.text = prefix + info
    }
}
