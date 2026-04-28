import requests
from bs4 import BeautifulSoup

url = "https://codeforces.com/contest/2225/problem/A"
html = requests.get(url).text

soup = BeautifulSoup(html, "html.parser")

stmt = soup.select_one(".problem-statement")

title = stmt.select_one(".title").text
input_spec = stmt.select_one(".input-specification").text
output_spec = stmt.select_one(".output-specification").text

samples = []
for sample in stmt.select(".sample-test"):
    inputs = [i.text for i in sample.select(".input pre")]
    outputs = [o.text for o in sample.select(".output pre")]
    samples.append({"input": inputs, "output": outputs})

print(title)
