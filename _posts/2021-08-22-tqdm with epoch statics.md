---
title: "tqdm with epoch statics"
description: " tqdm을 쓰면 원래 accuracy나 loss를 따로 찍어줘야한다. tqdm 내에서만 사용되는 변수를 update하는 것으로 이걸 해결해볼 수 있다. https&#x3A;//adamoudad.github.io/posts/progress_bar_with_tqdm/"
date: 2021-08-22T13:36:09.808Z
categoreis: ["Python"]
tags: ["PyTorch","tqdm"]
---
 tqdm을 쓰면 원래 accuracy나 loss를 따로 찍어줘야한다.
 tqdm 내에서만 사용되는 변수를 update하는 것으로 이걸 해결해볼 수 있다.
 
 https://adamoudad.github.io/posts/progress_bar_with_tqdm/